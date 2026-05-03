import CoreImage
import SwiftUI

/// Horizontal scrolling filter strip + inline strength slider.
/// FILTER-02 (strip), FILTER-03 (strength slider), FILTER-04 (long-press favorite).
struct FilterStripView: View {

    @Bindable var viewModel: EditorViewModel
    @State private var thumbnailCache = FilterThumbnailCache()
    @State private var thumbnailContext = CIContext(options: [.useSoftwareRenderer: false])
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var photoID: String = ""

    private var selectedFilterID: String? { viewModel.stack.filter?.filterID }
    private var orderedFilters: [Filter] { viewModel.filterLibrary.orderedFilters }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters").font(Theme.Typography.subtitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(orderedFilters) { filter in
                        thumbCell(for: filter)
                    }
                }
                .padding(.vertical, 4)
            }

            if let selID = selectedFilterID, selID != BuiltInLUTs.ID.identity {
                strengthSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: importedPhotoIdentity) {
            await regenerateThumbnails()
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func thumbCell(for filter: Filter) -> some View {
        let isSelected = (selectedFilterID == filter.id) ||
                         (selectedFilterID == nil && filter.id == BuiltInLUTs.ID.identity)
        let isFavorite = viewModel.filterLibrary.isFavorite(filter.id)

        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = thumbnails[filter.id] {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.Colors.panel)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Theme.Colors.accent : Color.clear, lineWidth: 3)
                        .animation(Motion.adaptive(Motion.snappy), value: isSelected)
                )

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .padding(4)
                }
            }
            Text(filter.displayName)
                .font(Theme.Typography.caption)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.Colors.text : Theme.Colors.secondary)
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedFilterID != filter.id { Haptic.play(.filterSelect) }
            viewModel.selectFilter(id: filter.id)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            viewModel.filterLibrary.toggleFavorite(filter.id)
            Haptic.play(.recipeApply)
        }
        .accessibilityLabel("\(filter.displayName) filter")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Strength

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Strength")
                    .font(Theme.Typography.subtitle)
                Spacer()
                Text("\(Int((viewModel.stack.filter?.strength ?? 1.0) * 100))%")
                    .font(Theme.Typography.valueBubble)
                    .foregroundStyle(Theme.Colors.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.stack.filter?.strength ?? 1.0 },
                    set: { viewModel.setFilterStrength($0) }
                ),
                in: 0...1
            )
            .tint(Theme.Colors.accent)
        }
        .padding(.top, 4)
    }

    // MARK: - Thumbnails

    /// Identity used to invalidate thumbnails when the photo changes.
    /// ImportedImage is a struct so we use previewCIImage extent as a stable heuristic.
    private var importedPhotoIdentity: String {
        guard let img = viewModel.importedImage else { return "" }
        return img.previewCIImage.extent.debugDescription
    }

    @MainActor
    private func regenerateThumbnails() async {
        guard let imported = viewModel.importedImage else {
            thumbnails = [:]
            photoID = ""
            return
        }
        let newID = importedPhotoIdentity
        if newID != photoID {
            thumbnailCache.clear()
            thumbnails = [:]
            photoID = newID
        }
        // Downsample preview source to thumbnail size for fast cube application.
        let src = imported.previewCIImage
        let side = FilterThumbnailCache.thumbnailSide
        let scale = side / max(src.extent.width, src.extent.height)
        let small = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        for filter in orderedFilters {
            if let cached = thumbnailCache.image(forPhotoID: photoID, filterID: filter.id) {
                thumbnails[filter.id] = cached
                continue
            }
            let cube = filter.cube()
            if let img = FilterThumbnailCache.renderThumbnail(
                source: small, cube: cube, strength: 1.0, context: thumbnailContext) {
                thumbnailCache.setImage(img, forPhotoID: photoID, filterID: filter.id)
                thumbnails[filter.id] = img
            }
            await Task.yield()
        }
    }
}
