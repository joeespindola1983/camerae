import Foundation

enum ZipWriter {
    static func write(files: [URL], baseURL: URL, to destinationURL: URL) throws {
        var archive = Data()
        var centralDirectory = Data()
        var centralRecords: [CentralRecord] = []

        for fileURL in files {
            let data = try Data(contentsOf: fileURL)
            let name = relativePath(for: fileURL, baseURL: baseURL)
            guard let nameData = name.data(using: .utf8) else { continue }

            let crc = CRC32.checksum(data)
            let offset = UInt32(archive.count)

            archive.appendUInt32LE(0x04034b50)
            archive.appendUInt16LE(20)
            archive.appendUInt16LE(0x0800)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt16LE(0)
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(UInt32(data.count))
            archive.appendUInt32LE(UInt32(data.count))
            archive.appendUInt16LE(UInt16(nameData.count))
            archive.appendUInt16LE(0)
            archive.append(nameData)
            archive.append(data)

            centralRecords.append(
                CentralRecord(
                    nameData: nameData,
                    crc: crc,
                    compressedSize: UInt32(data.count),
                    uncompressedSize: UInt32(data.count),
                    localHeaderOffset: offset
                )
            )
        }

        let centralDirectoryOffset = UInt32(archive.count)

        for record in centralRecords {
            centralDirectory.appendUInt32LE(0x02014b50)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(20)
            centralDirectory.appendUInt16LE(0x0800)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(record.crc)
            centralDirectory.appendUInt32LE(record.compressedSize)
            centralDirectory.appendUInt32LE(record.uncompressedSize)
            centralDirectory.appendUInt16LE(UInt16(record.nameData.count))
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt16LE(0)
            centralDirectory.appendUInt32LE(0)
            centralDirectory.appendUInt32LE(record.localHeaderOffset)
            centralDirectory.append(record.nameData)
        }

        archive.append(centralDirectory)

        archive.appendUInt32LE(0x06054b50)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(0)
        archive.appendUInt16LE(UInt16(centralRecords.count))
        archive.appendUInt16LE(UInt16(centralRecords.count))
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0)

        try archive.write(to: destinationURL, options: [.atomic])
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
}

private struct CentralRecord {
    let nameData: Data
    let crc: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
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

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xffffffff
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
}
