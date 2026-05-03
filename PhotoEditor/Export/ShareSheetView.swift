import SwiftUI
import UIKit

/// Presents a system share sheet for encoded export Data. Writes the bytes to
/// a temp file with the correct extension so destination apps see a real photo
/// file (some share extensions only accept URLs, not raw Data).
struct ShareSheetView: UIViewControllerRepresentable {
    let data: Data
    let format: ExportFormat
    var onDismiss: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = Self.writeTempFile(data: data, format: format)
        let items: [Any] = [tempURL].compactMap { $0 }
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        avc.completionWithItemsHandler = { _, _, _, _ in
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
            onDismiss?()
        }
        return avc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }

    private static func writeTempFile(data: Data, format: ExportFormat) -> URL? {
        let dir = FileManager.default.temporaryDirectory
        let name = "PhotoEditor-Export-\(UUID().uuidString).\(format.fileExtension)"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
