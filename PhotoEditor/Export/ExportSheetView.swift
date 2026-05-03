import SwiftUI

struct ExportSheetView: View {
    let viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .heic
    @State private var sizeChoice: SizeChoice = .full
    @State private var customLongEdge: String = "2048"
    @State private var quality: Double = 0.85

    enum SizeChoice: Hashable, CaseIterable {
        case full, web, story, custom
        var displayName: String {
            switch self {
            case .full: return "Full"
            case .web: return "Web (2048)"
            case .story: return "Story (1080)"
            case .custom: return "Custom"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases, id: \.self) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    if format == .png {
                        Text("PNG is lossless. Quality slider does not apply.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Size") {
                    Picker("Size", selection: $sizeChoice) {
                        ForEach(SizeChoice.allCases, id: \.self) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    if sizeChoice == .custom {
                        HStack {
                            Text("Long edge")
                            Spacer()
                            TextField("2048", text: $customLongEdge)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                        Text("Allowed: 256 to 8192").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if format.supportsQuality {
                    Section("Quality") {
                        HStack {
                            Slider(value: $quality, in: 0.4...1.0, step: 0.05)
                            Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 50, alignment: .trailing)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.saveExport(options: resolvedOptions); dismiss() }
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isExporting || !validCustomSize)

                    Button {
                        Task { await viewModel.shareExport(options: resolvedOptions); dismiss() }
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isExporting || !validCustomSize)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if viewModel.isExporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Exporting…").font(.callout)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private var validCustomSize: Bool {
        guard sizeChoice == .custom else { return true }
        guard let n = Int(customLongEdge) else { return false }
        return n >= 256 && n <= 8192
    }

    private var resolvedSize: ExportSize {
        switch sizeChoice {
        case .full: return .full
        case .web: return .web
        case .story: return .story
        case .custom:
            let raw = Int(customLongEdge) ?? 2048
            return .custom(longEdge: raw)
        }
    }

    private var resolvedOptions: ExportOptions {
        ExportOptions(format: format, size: resolvedSize, quality: quality)
    }
}
