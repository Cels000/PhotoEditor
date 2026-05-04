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
            // No rounded card chrome — panel is continuous with canvas, only
            // a single hairline separator distinguishes it from the photo area.
            .background(
                Theme.Colors.canvas
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Theme.Colors.separator)
                            .frame(height: 0.5)
                    }
            )
            .transition(.move(edge: .bottom))

            // Tab bar.
            tabBar
                .padding(.vertical, Theme.Spacing.xs)
        }
    }

    private var tabBar: some View {
        // VSCO-style: tiny UPPERCASE labels with letterspacing. Selection is
        // bold + accent text only — no pill, no underline, no decoration.
        // The chrome stays out of the photo's way.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.lg) {
                ForEach(EditorPanelTab.allCases) { tab in
                    Button {
                        guard selectedTab != tab else { return }
                        Haptic.play(.panelOpen)
                        withAnimation(Motion.adaptive(Motion.panel)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.displayName.uppercased())
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .foregroundStyle(selectedTab == tab ? Theme.Colors.text : Theme.Colors.secondary)
                            .padding(.vertical, Theme.Spacing.sm)
                            .frame(minWidth: 44)
                    }
                    .accessibilityLabel("\(tab.displayName) panel")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}
