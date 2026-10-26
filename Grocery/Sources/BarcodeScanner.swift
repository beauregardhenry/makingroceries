import SwiftUI
import VisionKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !handled else { return }
            for case .barcode(let barcode) in addedItems {
                if let code = barcode.payloadStringValue {
                    handled = true
                    onScan(code)
                    return
                }
            }
        }
    }
}

/// Camera scanner where the device supports it; otherwise a manual barcode field,
/// which is also how lookups can be tried in the Simulator.
struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    @State private var manualCode = ""

    private var cameraReady: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if cameraReady {
                    BarcodeScannerView { code in
                        onCode(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    Form {
                        Section {
                            Text("The camera scanner isn't available here. Check that camera access is allowed in Settings, or type the barcode number.")
                                .foregroundStyle(.secondary)
                        }
                        Section("Barcode") {
                            TextField("e.g. 3017620422003", text: $manualCode)
                                .keyboardType(.numberPad)
                            Button("Look Up") {
                                onCode(manualCode.trimmingCharacters(in: .whitespaces))
                                dismiss()
                            }
                            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
