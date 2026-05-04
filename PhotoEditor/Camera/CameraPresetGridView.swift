import SwiftUI

struct CameraPresetGridView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: CameraViewModel

    private struct GridSection: Identifiable {
        let id: String
        let title: String?
        let slots: [CameraSlot]
    }

    private var sections: [GridSection] {
        var result: [GridSection] = []
        let allSlots = viewModel.slots

        if let originalSlot = allSlots.first(where: {
            if case .original = $0 { return true } else { return false }
        }) {
            result.append(GridSection(id: "original", title: nil, slots: [originalSlot]))
        }

        for category in RecipeCategory.allCases {
            let slotsInCategory = allSlots.filter { $0.category == category }
            if !slotsInCategory.isEmpty {
                result.append(GridSection(
                    id: category.rawValue,
                    title: category.displayName.uppercased(),
                    slots: slotsInCategory
                ))
            }
        }

        let myRecipes = allSlots.filter { slot in
            if case .original = slot { return false }
            return slot.category == nil
        }
        if !myRecipes.isEmpty {
            result.append(GridSection(
                id: "my-recipes",
                title: "MY RECIPES",
                slots: myRecipes
            ))
        }

        return result
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: Theme.Spacing.md),
        GridItem(.flexible(), spacing: Theme.Spacing.md),
        GridItem(.flexible(), spacing: Theme.Spacing.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            if let title = section.title {
                                Text(title)
                                    .font(Theme.Typography.label)
                                    .tracking(2)
                                    .foregroundStyle(Theme.Colors.secondary)
                                    .padding(.horizontal, Theme.Spacing.lg)
                            }
                            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                                ForEach(section.slots) { slot in
                                    tile(for: slot)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.md)
            }
            .background(Theme.Colors.canvas)
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.Colors.text)
                    }
                }
            }
        }
        .onAppear {
            viewModel.thumbnailer?.setVisibleSlotIDs(Set(viewModel.slots.map(\.id)))
        }
    }

    @ViewBuilder
    private func tile(for slot: CameraSlot) -> some View {
        let isSelected = slot.id == viewModel.selectedSlotID
        let cg = viewModel.thumbnailer?.thumbnails[slot.id]
        Button {
            viewModel.selectSlot(slot)
            dismiss()
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                ZStack {
                    if let cg {
                        Image(cg, scale: 1, label: Text(slot.displayName))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Theme.Colors.secondary.opacity(0.2))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .overlay(
                    Rectangle()
                        .stroke(Theme.Colors.text, lineWidth: isSelected ? 2 : 0)
                )
                Text(slot.displayName.uppercased())
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.Colors.text)
            }
        }
        .buttonStyle(.plain)
    }
}
