import SwiftUI

/// Bottom segmented control + slide-up panel container.
/// CRITICAL: The container is laid out below the fixed-size canvas. Changing
/// the selected tab MUST NOT change the canvas frame. Panels are wrapped in a
/// fixed-height container with internal scrolling.
struct PanelContainerView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var selectedTab: EditorPanelTab

    // Fixed panel height — prevents canvas layout shift (Pitfall #19, UX-03).
    private let panelHeight: CGFloat = 280

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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: panelHeight)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.large, style: .continuous))
            .transition(.move(edge: .bottom))

            // Tab bar.
            tabBar
                .padding(.vertical, 8)
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(EditorPanelTab.allCases) { tab in
                    Button {
                        guard selectedTab != tab else { return }
                        Haptic.play(.panelOpen)
                        withAnimation(Motion.adaptive(Motion.panel)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.displayName)
                                .font(Theme.Typography.caption)
                        }
                        .foregroundStyle(selectedTab == tab ? Theme.Colors.accent : Theme.Colors.secondary)
                        .frame(width: 64)
                    }
                    .accessibilityLabel("\(tab.displayName) panel")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
