import AppKit

/// The JSON field keeps its historical name, but new documents are flat RTFD:
/// a self-contained document containing both attributed text and attachment bytes.
enum NookRichDocument {
    /// Only migrate a demonstrably composite rich stream. Never infer a title
    /// from ordinary body content, or discard unreadable data during a metadata edit.
    static func bodyData(for note: NookNote) -> Data? {
        guard let data = note.bodyRTF,
              let document = try? decode(data),
              document.string != note.body else { return note.bodyRTF }
        for prefix in [note.title + "\n", "\n"] {
            guard document.string == prefix + note.body else { continue }
            let range = NSRange(location: (prefix as NSString).length, length: (note.body as NSString).length)
            return (try? encode(document.attributedSubstring(from: range))) ?? data
        }
        return data
    }

    enum DocumentError: LocalizedError {
        case unreadableImage
        case missingAttachment

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "The image could not be read. Try a PNG or JPEG file."
            case .missingAttachment: return "An attachment could not be saved. The previous saved document has been kept."
            }
        }
    }

    static func decode(_ data: Data) throws -> NSAttributedString {
        let isLegacyRTF = data.starts(with: Data("{\\rtf".utf8))
        return try NSAttributedString(
            data: data,
            options: [.documentType: isLegacyRTF
                ? NSAttributedString.DocumentType.rtf
                : NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )
    }

    static func encode(_ value: NSAttributedString) throws -> Data {
        let document = NSMutableAttributedString(attributedString: value)
        let range = NSRange(location: 0, length: document.length)
        var failure: Error?
        document.enumerateAttribute(.attachment, in: range) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  attachment.fileWrapper == nil else { return }
            // AppKit drag/drop and third-party rich clipboard contents can
            // supply image-only attachments. Materialize them before writing.
            guard let image = attachment.image
                ?? (attachment.attachmentCell as? NSTextAttachmentCell)?.image else {
                failure = DocumentError.missingAttachment
                return
            }
            do {
                let saved = try imageAttachment(image)
                document.addAttribute(.attachment, value: saved, range: range)
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return try document.data(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtfd
        ])
    }

    static func imageAttachment(
        _ image: NSImage,
        filename: String = "Image.png",
        maxWidth: CGFloat = 320
    ) throws -> NSTextAttachment {
        guard image.size.width > 0, image.size.height > 0,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw DocumentError.unreadableImage
        }
        let scale = min(1, maxWidth / image.size.width)
        let displaySize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        // PNG resolution metadata carries the intended point size through
        // RTFD reloads; changing only the transient attachment cell does not.
        // Keep the original pixels so the photo remains sharp on Retina.
        bitmap.size = displaySize
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw DocumentError.unreadableImage
        }
        let wrapper = FileWrapper(regularFileWithContents: png)
        let stem = (filename as NSString).deletingPathExtension
        wrapper.preferredFilename = "\(stem.isEmpty ? "Image" : stem).png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let display = image.copy() as! NSImage
        display.size = displaySize
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: display)
        return attachment
    }
}
