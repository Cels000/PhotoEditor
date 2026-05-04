import SwiftUI

/// Bottom segmented control + slide-up panel container.
/// CRITICAL: The container is laid out below the fixed-size canvas. Changing
/// the selected tab MUST NOT change the canvas frame. Panels are wrapped in a
/// fixed-height container with internal scrolling.
struct PanelContainerView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var selectedTab: EditorPanelTab

    // Fixed panel height — prevents canvas layout shift (Pitfall #19, UX-03).
    // Tightened from 280 → 200 to give the canvas back screen real estate.
    private let panelHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Slide-up panel content (fixed height regardless of which tab).
            ZStack {
                Group {
                    switch selectedTab {
                    case .filters: FilterStripView(viewModel: viewModel)
                    case .light:   LightPanelView(viewModel: viewModel)
                    case .color:   ColorPanelView(viewModel: viewModel)
                    case .hsl:     HSLPanelView(viewModel: viewModel)
                    case .curves:  CurvesPanelView(viewModel: viewModel)
                    case .effects: EffectsPanelView(viewModel: viewModel)
                    case .crop:    CropPanelView(viewModel: viewModel) // 03-09
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .frame(height: panelHeight)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.large, style: .continuous))
            .transition(.move(edge: .bottom))

            // Tab bar.
            tabBar
                .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(EditorPanelTab.allCases) { tab in
                    Button {
                        guard selectedTab != tab else { return }
                        Haptic.play(.panelOpen)
                        withAnimation(Motion.adaptive(Motion.panel)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                            if selectedTab == tab {
                                Text(tab.displayName)
                                    .font(Theme.Typography.caption)
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? Theme.Colors.canvas : Theme.Colors.secondary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selectedTab == tab ? Theme.Colors.accent : Color.clear)
                        )
                    }
                    .accessibilityLabel("\(tab.displayName) panel")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}
