import SwiftUI
import VisionKit

/// At the store: scan each item as it goes in the cart and it's checked off your list.
struct ScanCheckOffView: View {
    @Environment(GroceryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let shopID: UUID?

    private struct Result: Equatable {
        enum Kind { case good, info, warning }
        var text: String
        var kind: Kind
        var detail: String?
    }

    @State private var result: Result?
    @State private var lastCode = ""
    @State private var lastTime = Date.distantPast
    @State private var manualCode = ""
    @State private var count = 0

    private var cameraReady: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if cameraReady {
                    BarcodeScannerView(continuous: true) { code in Task { await handle(code) } }
                        .ignoresSafeArea()
                } else {
                    Form {
                        Section {
                            Text("The camera scanner isn't available here. Type a barcode number to try it.")
                                .foregroundStyle(.secondary)
                            TextField("e.g. 3017620422003", text: $manualCode).keyboardType(.numberPad)
                            Button("Check Off") {
                                let code = manualCode.trimmingCharacters(in: .whitespaces)
                                manualCode = ""
                                Task { await handle(code) }
                            }
                            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                if let result {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(result.text, systemImage: symbol(result.kind)).font(.headline)
                        if let detail = result.detail { Text(detail).font(.subheadline) }
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color(result.kind), in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(count == 0 ? "Scan to Check Off" : "Checked off \(count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sensoryFeedback(.success, trigger: count)
            .animation(.default, value: result)
        }
    }

    private func symbol(_ kind: Result.Kind) -> String {
        switch kind {
        case .good: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ kind: Result.Kind) -> Color {
        switch kind {
        case .good: .green
        case .info: .gray
        case .warning: .orange
        }
    }

    private func handle(_ code: String) async {
        // The camera sees the same barcode many times a second.
        guard !code.isEmpty, !(code == lastCode && Date().timeIntervalSince(lastTime) < 3) else { return }
        lastCode = code
        lastTime = Date()

        var product: ScannedProduct?
        let outcome = await store.checkOff(barcode: code, preferring: shopID) { code in
            product = try? await ProductLookup.product(for: code)
            return product?.name
        }

        let warnings = product.map { AvoidList.warnings(allergens: $0.allergens, ingredients: $0.ingredients, avoid: AvoidList.words) } ?? []
        var extra = AvoidList.message(warnings)
        if case .ticked(let name) = outcome, extra == nil {
            extra = store.items.first { $0.name == name }?.warning
        }

        switch outcome {
        case .ticked(let name):
            count += 1
            result = Result(text: "Checked off \(name)", kind: extra == nil ? .good : .warning, detail: extra)
        case .alreadyBought(let name):
            result = Result(text: "\(name) is already checked off", kind: .info, detail: extra)
        case .notOnList(let name):
            result = Result(text: "\(name) isn't on your list", kind: extra == nil ? .info : .warning, detail: extra)
        case .unknown:
            result = Result(text: "Couldn't identify that barcode", kind: .info, detail: "Check your connection, or add it by name.")
        }
    }
}
