import Foundation

public struct EditProjectCodec: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> EditProjectDocument {
        let document = try Self.decoder().decode(EditProjectDocument.self, from: data)
        guard document.schemaVersion == 1 else {
            throw EditProjectCodecError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }

    public func encode(_ document: EditProjectDocument) throws -> Data {
        guard document.schemaVersion == 1 else {
            throw EditProjectCodecError.unsupportedSchema(document.schemaVersion)
        }
        return try Self.encoder().encode(document)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum EditProjectCodecError: Error, Equatable {
    case unsupportedSchema(Int)
}
