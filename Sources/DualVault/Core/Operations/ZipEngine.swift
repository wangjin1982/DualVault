import Foundation
import zlib

/// 自实现 ZIP 容器：本地文件头 + 中央目录 + EOCD，deflate 用系统 libz（raw）。
/// 支持 store(0) 与 deflate(8)，不支持加密/分卷。冲突命名由调用方经 ConflictResolver 提供。
enum ZipEngine {

    // MARK: - CRC32

    static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            return c
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - deflate / inflate（raw）

    static func deflate(_ data: Data) throws -> Data {
        var strm = z_stream()
        guard deflateInit2_(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8,
                            Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw OperationError.unexpected("deflate 初始化失败")
        }
        defer { deflateEnd(&strm) }
        var out = Data(count: Int(deflateBound(&strm, UInt(data.count))))
        let result = data.withUnsafeBytes { src -> Int32 in
            strm.next_in = UnsafeMutablePointer<Bytef>(mutating: src.bindMemory(to: Bytef.self).baseAddress!)
            strm.avail_in = UInt32(data.count)
            return out.withUnsafeMutableBytes { dst -> Int32 in
                strm.next_out = dst.bindMemory(to: Bytef.self).baseAddress!
                strm.avail_out = UInt32(dst.count)
                return zlib.deflate(&strm, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END else { throw OperationError.unexpected("deflate 失败 (\(result))") }
        out.count = Int(strm.total_out)
        return out
    }

    static func inflate(_ data: Data, expectedSize: UInt32) throws -> Data {
        var strm = z_stream()
        guard inflateInit2_(&strm, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw OperationError.unexpected("inflate 初始化失败")
        }
        defer { inflateEnd(&strm) }
        var out = Data(count: Int(expectedSize))
        let result = data.withUnsafeBytes { src -> Int32 in
            strm.next_in = UnsafeMutablePointer<Bytef>(mutating: src.bindMemory(to: Bytef.self).baseAddress!)
            strm.avail_in = UInt32(data.count)
            return out.withUnsafeMutableBytes { dst -> Int32 in
                strm.next_out = dst.bindMemory(to: Bytef.self).baseAddress!
                strm.avail_out = UInt32(dst.count)
                return zlib.inflate(&strm, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END else { throw OperationError.unexpected("inflate 失败 (\(result))，文件可能损坏") }
        return out
    }

    // MARK: - 压缩

    /// 把 sources（文件/目录，目录递归）压成 destination。条目名 = 各源 basename。
    static func zip(_ sources: [URL], to destination: URL, isCancelled: () -> Bool) throws {
        struct CentralEntry {
            let name: String
            let crc, compSize, uncompSize: UInt32
            let offset: UInt32
            let dosDate, dosTime: UInt16
        }
        let fm = FileManager.default
        fm.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var entries: [CentralEntry] = []
        var currentOffset: UInt32 = 0

        func collect(_ url: URL, arcName: String) throws {
            if isCancelled() { throw OperationError.cancelled }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
            let (dosDate, dosTime) = dosDateTime((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? Date())
            if isDir.boolValue {
                let dirName = arcName.hasSuffix("/") ? arcName : arcName + "/"
                entries.append(try writeEntry(name: dirName, data: Data(), isDirectory: true, dosDate: dosDate, dosTime: dosTime))
                for child in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] {
                    try collect(url.appendingPathComponent(child), arcName: dirName + child)
                }
            } else {
                let raw = try Data(contentsOf: url)
                entries.append(try writeEntry(name: arcName, data: raw, isDirectory: false, dosDate: dosDate, dosTime: dosTime))
            }
        }

        func writeEntry(name: String, data: Data, isDirectory: Bool, dosDate: UInt16, dosTime: UInt16) throws -> CentralEntry {
            let compressed = isDirectory ? Data() : try deflate(data)
            let crc = isDirectory ? 0 : crc32(data)
            let nameBytes = Array(name.utf8)
            var header = Data()
            header.appendLE(UInt32(0x04034b50)); header.appendLE(UInt16(20))
            header.appendLE(UInt16(0x0800))            // UTF-8 标志
            header.appendLE(UInt16(isDirectory ? 0 : 8)) // store / deflate
            header.appendLE(dosTime); header.appendLE(dosDate)
            header.appendLE(crc); header.appendLE(UInt32(compressed.count)); header.appendLE(UInt32(data.count))
            header.appendLE(UInt16(nameBytes.count)); header.appendLE(UInt16(0))
            header.append(contentsOf: nameBytes)
            try handle.write(contentsOf: header)
            try handle.write(contentsOf: compressed)
            let entry = CentralEntry(name: name, crc: crc, compSize: UInt32(compressed.count),
                                     uncompSize: UInt32(data.count), offset: currentOffset,
                                     dosDate: dosDate, dosTime: dosTime)
            currentOffset += UInt32(header.count + compressed.count)
            return entry
        }

        for source in sources {
            try collect(source, arcName: source.lastPathComponent)
        }

        // 中央目录
        var central = Data()
        let centralStart = currentOffset
        for e in entries {
            var c = Data()
            c.appendLE(UInt32(0x02014b50)); c.appendLE(UInt16(20)); c.appendLE(UInt16(20))
            c.appendLE(UInt16(0x0800)); c.appendLE(UInt16(e.name.hasSuffix("/") ? 0 : 8))
            c.appendLE(e.dosTime); c.appendLE(e.dosDate)
            c.appendLE(e.crc); c.appendLE(e.compSize); c.appendLE(e.uncompSize)
            let nb = Array(e.name.utf8)
            c.appendLE(UInt16(nb.count)); c.appendLE(UInt16(0)); c.appendLE(UInt16(0))
            c.appendLE(UInt16(0)); c.appendLE(UInt16(0)) // diskStart + internalAttr
            c.appendLE(UInt32(0)); c.appendLE(UInt32(e.offset)) // externalAttr + localHeaderOffset
            c.append(contentsOf: nb)
            central.append(c)
        }
        try handle.write(contentsOf: central)
        // EOCD
        var eocd = Data()
        eocd.appendLE(UInt32(0x06054b50)); eocd.appendLE(UInt16(0)); eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(entries.count)); eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(central.count)); eocd.appendLE(UInt32(centralStart)); eocd.appendLE(UInt16(0))
        try handle.write(contentsOf: eocd)
    }

    // MARK: - 解压

    struct ZipEntry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let uncompSize: UInt32
        let compSize: UInt32
        let dataOffset: UInt32
        let modified: Date
        let encrypted: Bool
        var isDirectory: Bool { name.hasSuffix("/") }
    }

    enum ZipError: Error, Equatable {
        case encrypted
    }

    /// 解析中央目录（冲突预检与解压共用）。
    static func entries(of archive: URL) throws -> [ZipEntry] {
        let data = try Data(contentsOf: archive)
        guard data.count >= 22 else { throw OperationError.unexpected("不是有效的 zip 文件") }
        // 从尾部找 EOCD
        var eocdOffset = -1
        let scanStart = max(0, data.count - 66_000)
        for i in stride(from: data.count - 22, through: scanStart, by: -1) {
            if data.readLEUInt32(at: i) == 0x06054b50 { eocdOffset = i; break }
        }
        guard eocdOffset >= 0 else { throw OperationError.unexpected("zip 中央目录缺失（可能分卷/损坏）") }
        let count = Int(data.readLEUInt16(at: eocdOffset + 10))
        var pos = Int(data.readLEUInt32(at: eocdOffset + 16))
        var entries: [ZipEntry] = []
        var anyEncrypted = false
        for _ in 0..<count {
            guard data.readLEUInt32(at: pos) == 0x02014b50 else { break }
            let gpFlags = data.readLEUInt16(at: pos + 8)
            if gpFlags & 0x01 != 0 { anyEncrypted = true }
            let method = data.readLEUInt16(at: pos + 10)
            let compSize = data.readLEUInt32(at: pos + 20)
            let uncompSize = data.readLEUInt32(at: pos + 24)
            let nameLen = Int(data.readLEUInt16(at: pos + 28))
            let extraLen = Int(data.readLEUInt16(at: pos + 30))
            let commentLen = Int(data.readLEUInt16(at: pos + 32))
            let localOffset = Int(data.readLEUInt32(at: pos + 42))
            let name = String(decoding: data[(pos + 46)..<(pos + 46 + nameLen)], as: UTF8.self)
            // 本地头里 extra 长度可能与中央目录不同，按本地头算数据偏移
            let localNameLen = Int(data.readLEUInt16(at: localOffset + 26))
            let localExtraLen = Int(data.readLEUInt16(at: localOffset + 28))
            let dataOffset = localOffset + 30 + localNameLen + localExtraLen
            let dosDate = data.readLEUInt16(at: pos + 12)
            let dosTime = data.readLEUInt16(at: pos + 14)
            entries.append(ZipEntry(name: name, method: method, crc: data.readLEUInt32(at: pos + 16),
                                    uncompSize: uncompSize, compSize: compSize,
                                    dataOffset: UInt32(dataOffset),
                                    modified: Self.date(fromDosDate: dosDate, dosTime: dosTime),
                                    encrypted: gpFlags & 0x01 != 0))
            pos += 46 + nameLen + extraLen + commentLen
        }
        if anyEncrypted {
            throw ZipError.encrypted
        }
        return entries
    }

    /// 解压。resolveName 把条目名映射为落盘名（冲突策略），返回 nil 跳过。
    static func unzip(_ archive: URL, to destination: URL,
                      isCancelled: () -> Bool,
                      resolveName: (String) -> String?) throws -> [URL] {
        let fm = FileManager.default
        let data = try Data(contentsOf: archive)
        var written: [URL] = []
        for entry in try entries(of: archive) {
            if isCancelled() { throw OperationError.cancelled }
            guard let safeName = sanitize(entry.name),
                  let resolved = resolveName(safeName) else { continue }
            let target = destination.appendingPathComponent(resolved)
            if entry.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let raw = data[Int(entry.dataOffset)..<(Int(entry.dataOffset) + Int(entry.compSize))]
            let payload: Data
            switch entry.method {
            case 0: payload = Data(raw)
            case 8: payload = try inflate(Data(raw), expectedSize: entry.uncompSize)
            default: throw OperationError.unexpected("不支持的压缩方式 (\(entry.method))：\(entry.name)")
            }
            // CRC 校验（中央目录值）
            guard ZipEngine.crc32(payload) == entry.crc else {
                throw OperationError.unexpected("CRC 校验失败：\(entry.name)")
            }
            try payload.write(to: target)
            written.append(target)
        }
        return written
    }

    /// 防 zip-slip：含 ".." 成分一律拒绝，同时去掉空段。
    static func sanitize(_ name: String) -> String? {
        let parts = name.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        let cleaned = parts.filter { !$0.isEmpty && $0 != "." }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: "/")
    }

    /// DOS 日期时间 → Date（冲突对话框"源修改时间"用，本地时区）。
    static func date(fromDosDate d: UInt16, dosTime t: UInt16) -> Date {
        var components = tm()
        components.tm_year = Int32((d >> 9) & 0x7F) + 80   // 1980 起算
        components.tm_mon = Int32((d >> 5) & 0x0F) - 1
        components.tm_mday = Int32(d & 0x1F)
        components.tm_hour = Int32(t >> 11)
        components.tm_min = Int32((t >> 5) & 0x3F)
        components.tm_sec = Int32(t & 0x1F) * 2
        components.tm_isdst = -1
        let seconds = mktime(&components)
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        var t = tm()
        var time = time_t(date.timeIntervalSince1970)
        localtime_r(&time, &t)
        let dosTime = UInt16((Int(t.tm_hour) << 11) | (Int(t.tm_min) << 5) | (Int(t.tm_sec) >> 1))
        let year = Int(t.tm_year) + 1900
        let month = Int(t.tm_mon) + 1
        let day = Int(t.tm_mday)
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosDate, dosTime)
    }
}

// MARK: - 小端读写

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    func readLEUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readLEUInt32(at offset: Int) -> UInt32 {
        UInt32(readLEUInt16(at: offset)) | (UInt32(readLEUInt16(at: offset + 2)) << 16)
    }
}
