#!/usr/bin/env ruby
# frozen_string_literal: true

# Thin App Store Connect API client for release.sh.
#
# Subcommands:
#   list-apps                              — print appstoreconnect apps with numeric IDs
#   list-groups APP_ID                     — print beta groups for an app
#   find-build APP_ID VERSION BUILD [TIMEOUT_S]
#                                           — poll until the build appears, print its id
#   add-to-groups BUILD_ID GROUP_IDS       — assign build to a comma-separated list of groups
#
# Auth via env vars (release.sh exports the same defaults):
#   ASC_API_KEY_PATH   path to .p8 private key
#   ASC_API_KEY_ID     ten-character key id
#   ASC_API_ISSUER_ID  issuer uuid
#
# All output goes to stdout; errors / progress to stderr so callers can capture
# the discovered id without filtering.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

API_BASE = 'https://api.appstoreconnect.apple.com/v1'

def env_or_die(name)
  v = ENV[name]
  abort "Missing env var: #{name}" if v.nil? || v.empty?
  v
end

# Build a short-lived JWT signed with the App Store Connect ES256 .p8 key.
# Apple caps token lifetime at 20 minutes; we use 15 to leave slack for
# polling loops that re-issue when needed.
def asc_jwt
  key_id   = env_or_die('ASC_API_KEY_ID')
  issuer   = env_or_die('ASC_API_ISSUER_ID')
  key_path = env_or_die('ASC_API_KEY_PATH')

  key  = OpenSSL::PKey::EC.new(File.read(key_path))
  now  = Time.now.to_i
  hdr  = { alg: 'ES256', kid: key_id, typ: 'JWT' }
  body = { iss: issuer, iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' }

  hdr_b64  = Base64.urlsafe_encode64(JSON.dump(hdr),  padding: false)
  body_b64 = Base64.urlsafe_encode64(JSON.dump(body), padding: false)
  input    = "#{hdr_b64}.#{body_b64}"

  # OpenSSL signs ES256 as DER-encoded ASN.1; JWT requires raw R||S
  # concatenation with each component left-padded to 32 bytes.
  digest  = OpenSSL::Digest::SHA256.digest(input)
  der     = key.dsa_sign_asn1(digest)
  asn1    = OpenSSL::ASN1.decode(der)
  r_bytes = asn1.value[0].value.to_s(2).rjust(32, "\x00".b)
  s_bytes = asn1.value[1].value.to_s(2).rjust(32, "\x00".b)
  sig_b64 = Base64.urlsafe_encode64(r_bytes + s_bytes, padding: false)

  "#{input}.#{sig_b64}"
end

def asc_request(method, path, query: {}, body: nil)
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(query) unless query.empty?

  req = case method
        when :get  then Net::HTTP::Get.new(uri)
        when :post then Net::HTTP::Post.new(uri)
        else abort "unsupported method: #{method}"
        end
  req['Authorization'] = "Bearer #{asc_jwt}"
  req['Accept']        = 'application/json'
  if body
    req['Content-Type'] = 'application/json'
    req.body = JSON.dump(body)
  end

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  unless res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPNoContent)
    warn "ASC API #{method.upcase} #{path} → #{res.code}: #{res.body}"
    abort 'asc-api-error'
  end
  res.body && !res.body.empty? ? JSON.parse(res.body) : nil
end

def cmd_list_apps
  data = asc_request(:get, '/apps', query: { 'fields[apps]' => 'name,bundleId' })
  data['data'].each do |app|
    puts "#{app['id']}\t#{app['attributes']['bundleId']}\t#{app['attributes']['name']}"
  end
end

def cmd_list_groups(app_id)
  data = asc_request(
    :get,
    '/betaGroups',
    query: {
      'filter[app]' => app_id,
      'fields[betaGroups]' => 'name,isInternalGroup,publicLinkEnabled',
      'limit' => 100
    }
  )
  data['data'].each do |g|
    a = g['attributes']
    flags = [a['isInternalGroup'] ? 'internal' : 'external',
             a['publicLinkEnabled'] ? 'public-link' : nil].compact.join(',')
    puts "#{g['id']}\t#{a['name']}\t(#{flags})"
  end
end

def cmd_find_build(app_id, version, build, timeout = 1200)
  deadline = Time.now + timeout.to_i
  warn "Polling App Store Connect for build #{version} (#{build})..."
  loop do
    data = asc_request(
      :get,
      '/builds',
      query: {
        'filter[app]' => app_id,
        'filter[version]' => build,
        'filter[preReleaseVersion.version]' => version,
        'fields[builds]' => 'version,uploadedDate,processingState',
        'limit' => 1
      }
    )
    if data['data'] && !data['data'].empty?
      b = data['data'].first
      warn "  build registered: #{b['id']} (state=#{b['attributes']['processingState']})"
      puts b['id']
      return
    end
    if Time.now > deadline
      abort "Timed out waiting for build #{version} (#{build}) to appear"
    end
    sleep 30
    warn '  still waiting...'
  end
end

def cmd_add_to_groups(build_id, group_ids_csv)
  group_ids = group_ids_csv.split(',').map(&:strip).reject(&:empty?)
  abort 'no group ids provided' if group_ids.empty?
  body = { data: group_ids.map { |id| { type: 'betaGroups', id: id } } }
  asc_request(:post, "/builds/#{build_id}/relationships/betaGroups", body: body)
  warn "  assigned build #{build_id} to #{group_ids.length} group(s)"
end

cmd, *rest = ARGV
case cmd
when 'list-apps'      then cmd_list_apps
when 'list-groups'    then cmd_list_groups(rest.fetch(0) { abort 'usage: list-groups APP_ID' })
when 'find-build'     then cmd_find_build(*rest)
when 'add-to-groups'  then cmd_add_to_groups(*rest)
else
  warn 'usage: asc.rb {list-apps|list-groups|find-build|add-to-groups} ...'
  exit 1
end
