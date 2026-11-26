import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Single-selection import, in copy mode. Accept all file types in the picker
// because pairing records can use an unregistered extension or provider UTI.
// The existing bounded plist parser remains the actual content-validation gate.
struct TCPairingPicker: UIViewControllerRepresentable {
    let selected: (URL) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Delegate {
        Delegate(selected: selected, cancelled: cancelled)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Delegate: NSObject, UIDocumentPickerDelegate {
        private let selected: (URL) -> Void
        private let cancelled: () -> Void
        private var finished = false

        init(selected: @escaping (URL) -> Void, cancelled: @escaping () -> Void) {
            self.selected = selected
            self.cancelled = cancelled
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }
            finished = true
            guard let url = urls.first else { cancelled(); return }
            selected(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            cancelled()
        }
    }
}
