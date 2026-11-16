import Foundation

nonisolated enum LargeFileType: String, CaseIterable, Sendable {
    case installer = "Instaladores (.dmg, .pkg, .iso)"
    case video = "Vídeos e Mídias"
    case archive = "Arquivos Compactados (.zip, .tar, .gz)"
    case diskImage = "Imagens de Disco"
    case documents = "Documentos e Dados"
    case code = "Binários e Projetos"
    case other = "Outros Arquivos Grandes"

    var title: String {
        switch self {
        case .installer: return localized("Installers (.dmg, .pkg, .iso)")
        case .video: return localized("Videos and Media")
        case .archive: return localized("Compressed Archives (.zip, .tar, .gz)")
        case .diskImage: return localized("Disk Images")
        case .documents: return localized("Documents and Data")
        case .code: return localized("Binaries and Projects")
        case .other: return localized("Other Large Files")
        }
    }

    var systemIcon: String {
        switch self {
        case .installer: return "shippingbox.circle"
        case .video: return "film"
        case .archive: return "doc.zipper"
        case .diskImage: return "opticaldisc"
        case .documents: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        }
    }

    static func detect(for url: URL) -> LargeFileType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "dmg", "pkg", "iso":
            return .installer
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return .video
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar":
            return .archive
        case "sparseimage", "sparsebundle", "img", "vmdk", "qcow2":
            return .diskImage
        case "pdf", "pages", "numbers", "key", "psd", "sketch", "blend":
            return .documents
        case "o", "dylib", "so", "a", "framework":
            return .code
        default:
            return .other
        }
    }
}

nonisolated struct LargeFileItem: CleanupListItem, Equatable {
    let id: UUID
    let name: String
    let url: URL
    let size: Int64
    let fileType: LargeFileType
    let lastModified: Date
    var isSelected: Bool

    var formattedSize: String {
        Formatting.bytes(size)
    }

    var formattedDate: String {
        Formatting.relativeDate(lastModified)
    }

    var typeName: String { fileType.title }
    var itemURL: URL { url }
    var itemName: String { name }
    var itemSize: Int64 { size }

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        size: Int64,
        fileType: LargeFileType,
        lastModified: Date,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.size = size
        self.fileType = fileType
        self.lastModified = lastModified
        self.isSelected = isSelected
    }
}
