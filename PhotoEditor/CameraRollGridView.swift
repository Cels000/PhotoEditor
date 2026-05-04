// CameraRollGridView.swift
// Inline PHAsset thumbnail grid for the Studio → CAMERA ROLL segment.
// Replaces the v1 "tap to pick" tile with an actual scrollable preview of
// the user's photo library — one tap to import.
//
// Photos framework hookup:
// - PHFetchResult<PHAsset> sourced from the .smartAlbum.userLibrary (the
//   default Camera Roll). Sorted creationDate desc so newest is first.
// - PHCachingImageManager pre-fetches thumbs for visible cells; cells request
//   their own thumbnail when they appear.
// - On tap: PHImageManager.requestImageDataAndOrientation -> Data, passed to
//   viewModel.importPhoto with the asset's localIdentifier as sourceAssetID
//   (matches the format LibraryStore expects, so re-saves can find originals).
//
// Auth state handling:
// - .authorized / .limited → render grid (limited shows only the selected
//   subset, plus a "Manage Selection" affordance).
// - other states → render a permission prompt.

import Photos
import SwiftUI
import UIKit

struct CameraRollGridView: View {
    @Bindable var viewModel: EditorViewModel
    var onPhotoOpened: () -> Void

    @State private var assets: PHFetchResult<PHAsset>?
    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var isImporting: Bool = false

    private static let thumbCache = PHCachingImageManager()
    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3
    )

    var body: some View {
        Group {
            switch authStatus {
            case .authorized, .limited:
                grid
            case .denied, .restricted:
                deniedState
            case .notDetermined:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                deniedState
            }
        }
        .onAppear { refreshAuthAndAssets() }
        .overlay {
            if isImporting {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        if let assets, assets.count > 0 {
            ScrollView {
                if authStatus == .limited {
                    limitedBanner
                }
                LazyVGrid(columns: Self.columns, spacing: 2) {
                    ForEach(0..<assets.count, id: \.self) { index in
                        let asset = assets.object(at: index)
                        AssetThumbCell(asset: asset)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { handleTap(asset) }
                    }
                }
            }
        } else {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Theme.Colors.secondary)
                Text("NO PHOTOS")
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(Theme.Colors.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var limitedBanner: some View {
        Button {
            PhotoLibraryAccess.presentLimitedPicker()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.Colors.text)
                Text("Limited access — tap to manage selected photos")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.panel)
        }
        .buttonStyle(.plain)
    }

    private var deniedState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Colors.secondary)
            Text("PHOTOS ACCESS DENIED")
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.text)
            Text("Open Settings → PhotoEditor → Photos and choose All Photos.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("OPEN SETTINGS")
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(Theme.Colors.canvas)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func refreshAuthAndAssets() {
        authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authStatus == .authorized || authStatus == .limited else {
            assets = nil
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // .smartAlbum / .userLibrary returns the Camera Roll album.
        let album = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil
        ).firstObject
        if let album {
            assets = PHAsset.fetchAssets(in: album, options: options)
        } else {
            assets = PHAsset.fetchAssets(with: .image, options: options)
        }
    }

    private func handleTap(_ asset: PHAsset) {
        guard !isImporting else { return }
        isImporting = true
        let assetID = asset.localIdentifier

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true       // iCloud Photo Library originals
        opts.deliveryMode = .highQualityFormat
        opts.isSynchronous = false

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, _ in
            guard let data else {
                Task { @MainActor in
                    self.isImporting = false
                    self.viewModel.errorMessage = "The selected photo could not be loaded."
                }
                return
            }
            Task { @MainActor in
                await self.viewModel.importPhoto(data: data, sourceAssetID: assetID)
                self.isImporting = false
                self.onPhotoOpened()
            }
        }
    }
}

// MARK: - Cell

private struct AssetThumbCell: View {
    let asset: PHAsset

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.Colors.panel
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .onAppear { loadThumb() }
    }

    private func loadThumb() {
        guard image == nil else { return }
        let scale = UIScreen.main.scale
        // Square thumb sized for ~3-column grid. Slight overshoot for retina.
        let targetSide = CGFloat(180) * scale
        let target = CGSize(width: targetSide, height: targetSide)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = false
        PHImageManager.default().requestImage(
            for: asset, targetSize: target, contentMode: .aspectFill, options: opts
        ) { result, _ in
            if let result {
                Task { @MainActor in self.image = result }
            }
        }
    }
}
