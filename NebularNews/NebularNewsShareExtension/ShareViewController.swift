import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension for clipping URLs to NebularNews.
///
/// When a user shares a URL from Safari (or any app), this extension
/// sends it to the NebularNews API which scrapes and saves the article.
///
/// Auth: reads the session token from the shared Keychain access group.
class ShareViewController: UIViewController {

    private let apiBaseURL = "https://api.nebularnews.com"
    private let keychainService = "com.nebularnews.ios"
    private let keychainTokenKey = "session_token"

    private var statusLabel: UILabel!
    private var activityIndicator: UIActivityIndicatorView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        processShareInput()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.startAnimating()
        stack.addArrangedSubview(activityIndicator)

        statusLabel = UILabel()
        statusLabel.text = "Saving to NebularNews..."
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Process Share

    private func processShareInput() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("No content to share")
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.clipURL(url.absoluteString)
                            } else if let urlString = item as? String {
                                self?.clipURL(urlString)
                            } else {
                                self?.showError("Could not read URL")
                            }
                        }
                    }
                    return
                }
            }
        }

        showError("No URL found to clip")
    }

    // MARK: - API Call

    private func clipURL(_ urlString: String) {
        guard let token = readSessionToken() else {
            showError("Please sign in to NebularNews first")
            return
        }

        Task {
            do {
                try await performClip(url: urlString, token: token)
                showSuccess()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func performClip(url: String, token: String) async throws {
        guard let apiURL = URL(string: "\(apiBaseURL)/api/articles/clip") else {
            throw ClipError.invalidURL
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["url": url])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            if let body = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw ClipError.serverError(body.error.message)
            }
            throw ClipError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - Keychain

    private func readSessionToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Result UI

    private func showSuccess() {
        activityIndicator.stopAnimating()
        statusLabel.text = "Saved!"

        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .systemGreen
        checkmark.contentMode = .scaleAspectFit
        checkmark.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        checkmark.center = activityIndicator.center
        view.addSubview(checkmark)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError(_ message: String) {
        activityIndicator.stopAnimating()
        statusLabel.text = message
        statusLabel.textColor = .systemRed

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: ClipError.serverError(message))
        }
    }
}

// MARK: - Types

private enum ClipError: LocalizedError {
    case invalidURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .serverError(let msg): return msg
        }
    }
}

private struct ErrorResponse: Decodable {
    struct Detail: Decodable {
        let message: String
    }
    let error: Detail
}
