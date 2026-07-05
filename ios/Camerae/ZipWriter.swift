import Darwin
import Foundation

enum ZipWriter {
    private static let bufferSize = 256 * 1024

    static func write(files: [URL], baseURL: URL, to destinationURL: URL) throws {
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(destinationURL.lastPathComponent).tmp")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }

        let fd = open(temporaryURL.path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw ZipWriterError.cannotOpenFile(temporaryURL.path)
        }

        var writer = StreamingZipFile(fileDescriptor: fd)

        do {
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            for fileURL in files {
                let name = relativePath(for: fileURL, baseURL: baseURL)
                try writer.append(fileURL: fileURL, name: name, buffer: &buffer)
            }

            try writer.finish()
            close(fd)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            close(fd)
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func relativePath(for fileURL: URL, baseURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        if filePath.hasPrefix(basePath) {
            let start = filePath.index(filePath.startIndex, offsetBy: basePath.count)
            return String(filePath[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return fileURL.lastPathComponent
    }

    private struct StreamingZipFile {
        let fileDescriptor: Int32
        var offset: UInt64 = 0
        var records: [CentralRecord] = []

        mutating func append(fileURL: URL, name: String, buffer: inout [UInt8]) throws {
            guard let nameData = name.data(using: .utf8) else {
                throw ZipWriterError.invalidFileName(name)
            }

            let stats = try CRC32.checksumAndSize(of: fileURL, buffer: &buffer)
            let localHeaderOffset = offset
            try write(localHeader(nameData: nameData, crc: stats.crc, size: stats.size))
            try copy(fileURL, buffer: &buffer)

            records.append(CentralRecord(
                nameData: nameData,
                crc: stats.crc,
                compressedSize: stats.size,
                uncompressedSize: stats.size,
                localHeaderOffset: localHeaderOffset
            ))
        }

        mutating func finish() throws {
            let centralDirectoryOffset = offset

            for record in records {
                try write(centralHeader(for: record))
            }

            let centralDirectorySize = offset - centralDirectoryOffset
            let zip64EndOffset = offset
            try write(zip64EndRecord(
                entryCount: UInt64(records.count),
                centralDirectorySize: centralDirectorySize,
                centralDirectoryOffset: centralDirectoryOffset
            ))
            try write(zip64Locator(zip64EndOffset: zip64EndOffset))
            try write(endRecord())
        }

        private mutating func copy(_ fileURL: URL, buffer: inout [UInt8]) throws {
            let inputFD = open(fileURL.path, O_RDONLY)
            guard inputFD >= 0 else {
                throw ZipWriterError.cannotOpenFile(fileURL.path)
            }
            defer { close(inputFD) }

            while true {
                let count = buffer.withUnsafeMutableBufferPointer { pointer in
                    read(inputFD, pointer.baseAddress, pointer.count)
                }

                if count == 0 {
                    break
                }

                guard count > 0 else {
                    throw ZipWriterError.cannotReadFile(fileURL.path)
                }

                try write(buffer, count: count)
            }
        }

        private mutating func write(_ data: Data) throws {
            try data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                try writeAll(baseAddress, count: bytes.count)
            }
            offset += UInt64(data.count)
        }

        private mutating func write(_ buffer: [UInt8], count: Int) throws {
            try buffer.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                try writeAll(baseAddress, count: count)
            }
            offset += UInt64(count)
        }

        private func writeAll(_ baseAddress: UnsafeRawPointer, count: Int) throws {
            var written = 0
            while written < count {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: written),
                    count - written
                )

                guard result > 0 else {
                    throw ZipWriterError.cannotWriteFile
                }

                written += result
            }
        }

        private func localHeader(nameData: Data, crc: UInt32, size: UInt64) -> Data {
            var data = Data()
            let extra = zip64Extra(uncompressedSize: size, compressedSize: size, localHeaderOffset: nil)

            data.appendUInt32LE(0x04034b50)
            data.appendUInt16LE(45)
            data.appendUInt16LE(0x0800)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(crc)
            data.appendUInt32LE(UInt32.max)
            data.appendUInt32LE(UInt32.max)
            data.appendUInt16LE(UInt16(nameData.count))
            data.appendUInt16LE(UInt16(extra.count))
            data.append(nameData)
            data.append(extra)
            return data
        }

        private func centralHeader(for record: CentralRecord) -> Data {
            var data = Data()
            let extra = zip64Extra(
                uncompressedSize: record.uncompressedSize,
                compressedSize: record.compressedSize,
                localHeaderOffset: record.localHeaderOffset
            )

            data.appendUInt32LE(0x02014b50)
            data.appendUInt16LE(45)
            data.appendUInt16LE(45)
            data.appendUInt16LE(0x0800)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(record.crc)
            data.appendUInt32LE(UInt32.max)
            data.appendUInt32LE(UInt32.max)
            data.appendUInt16LE(UInt16(record.nameData.count))
            data.appendUInt16LE(UInt16(extra.count))
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt32LE(0)
            data.appendUInt32LE(UInt32.max)
            data.append(record.nameData)
            data.append(extra)
            return data
        }

        private func zip64Extra(
            uncompressedSize: UInt64,
            compressedSize: UInt64,
            localHeaderOffset: UInt64?
        ) -> Data {
            var payload = Data()
            payload.appendUInt64LE(uncompressedSize)
            payload.appendUInt64LE(compressedSize)
            if let localHeaderOffset {
                payload.appendUInt64LE(localHeaderOffset)
            }

            var data = Data()
            data.appendUInt16LE(0x0001)
            data.appendUInt16LE(UInt16(payload.count))
            data.append(payload)
            return data
        }

        private func zip64EndRecord(
            entryCount: UInt64,
            centralDirectorySize: UInt64,
            centralDirectoryOffset: UInt64
        ) -> Data {
            var data = Data()
            data.appendUInt32LE(0x06064b50)
            data.appendUInt64LE(44)
            data.appendUInt16LE(45)
            data.appendUInt16LE(45)
            data.appendUInt32LE(0)
            data.appendUInt32LE(0)
            data.appendUInt64LE(entryCount)
            data.appendUInt64LE(entryCount)
            data.appendUInt64LE(centralDirectorySize)
            data.appendUInt64LE(centralDirectoryOffset)
            return data
        }

        private func zip64Locator(zip64EndOffset: UInt64) -> Data {
            var data = Data()
            data.appendUInt32LE(0x07064b50)
            data.appendUInt32LE(0)
            data.appendUInt64LE(zip64EndOffset)
            data.appendUInt32LE(1)
            return data
        }

        private func endRecord() -> Data {
            var data = Data()
            data.appendUInt32LE(0x06054b50)
            data.appendUInt16LE(0)
            data.appendUInt16LE(0)
            data.appendUInt16LE(UInt16.max)
            data.appendUInt16LE(UInt16.max)
            data.appendUInt32LE(UInt32.max)
            data.appendUInt32LE(UInt32.max)
            data.appendUInt16LE(0)
            return data
        }
    }
}

private struct CentralRecord {
    let nameData: Data
    let crc: UInt32
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let localHeaderOffset: UInt64
}

private enum ZipWriterError: LocalizedError {
    case invalidFileName(String)
    case cannotOpenFile(String)
    case cannotReadFile(String)
    case cannotWriteFile

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            return "nome de arquivo invalido para ZIP"
        case .cannotOpenFile:
            return "nao foi possivel abrir arquivo para ZIP"
        case .cannotReadFile:
            return "nao foi possivel ler arquivo para ZIP"
        case .cannotWriteFile:
            return "nao foi possivel gravar o ZIP"
        }
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0...255).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xedb88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksumAndSize(of fileURL: URL, buffer: inout [UInt8]) throws -> (crc: UInt32, size: UInt64) {
        let inputFD = open(fileURL.path, O_RDONLY)
        guard inputFD >= 0 else {
            throw ZipWriterError.cannotOpenFile(fileURL.path)
        }
        defer { close(inputFD) }

        var crc: UInt32 = 0xffffffff
        var size: UInt64 = 0

        while true {
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                read(inputFD, pointer.baseAddress, pointer.count)
            }

            if count == 0 {
                break
            }

            guard count > 0 else {
                throw ZipWriterError.cannotReadFile(fileURL.path)
            }

            size += UInt64(count)
            update(&crc, bytes: buffer, count: count)
        }

        return (crc ^ 0xffffffff, size)
    }

    private static func update(_ crc: inout UInt32, bytes: [UInt8], count: Int) {
        bytes.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            for index in 0..<count {
                let tableIndex = Int((crc ^ UInt32(baseAddress[index])) & 0xff)
                crc = (crc >> 8) ^ table[tableIndex]
            }
        }
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 32) & 0xff))
        append(UInt8((value >> 40) & 0xff))
        append(UInt8((value >> 48) & 0xff))
        append(UInt8((value >> 56) & 0xff))
    }
}
