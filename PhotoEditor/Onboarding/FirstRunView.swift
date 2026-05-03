import SwiftUI

struct FirstRunView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Image(systemName: "camera.aperture")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Theme.Colors.accent)
            Text("Welcome to PhotoEditor")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                row(icon: "photo.on.rectangle", title: "Pick a photo to edit",
                    body: "iOS will ask for permission the first time you tap the photo picker.")
                row(icon: "slider.horizontal.3", title: "Adjust with film-style filters",
                    body: "Distinctive LUTs, full light + color controls, save your favorite looks as Recipes.")
                row(icon: "tray.and.arrow.down", title: "Save back to Photos",
                    body: "Edits are non-destructive — your originals are never modified.")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            Spacer()
            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(Theme.Typography.subtitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.medium))
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
            .accessibilityLabel("Get started — dismiss welcome screen")
        }
        .background(Theme.Colors.canvas.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func row(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typography.subtitle).foregroundStyle(Theme.Colors.text)
                Text(body).font(Theme.Typography.body).foregroundStyle(Theme.Colors.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
