import SwiftUI
import UniformTypeIdentifiers

struct FeedOPMLDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [opmlContentType, .xml, .plainText]
    }

    static var writableContentTypes: [UTType] {
        [opmlContentType]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    private static var opmlContentType: UTType {
        UTType(filenameExtension: "opml") ?? .xml
    }
}
