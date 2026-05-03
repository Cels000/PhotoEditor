// LibraryItemThumbnail.swift
// PhotoEditor
//
// Single cell in LibraryGridView. Shows the stored thumbnail JPEG. If the
// underlying PHAsset has been deleted (LIB-05), shows an "unavailable" overlay
// instead of a broken-looking image.

import SwiftUI
import UIKit
import Photos

struct LibraryItemThumbnail: View {
    let item: LibraryItem

    @State private var sourceAvailable: Bool = true

    var body: some View {
        ZStack {
            if let data = item.thumbnailData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.tertiarySystemBackground))
            }

            if !sourceAvailable {
                // Dim + warning overlay — communicates "source gone, read-only".
                Color.black.opacity(0.55)
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                    Text("Source unavailable")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(6)
            }

            // Edited badge — every library item is by definition an edit; the
            // badge makes that visible at a glance.
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                        .accessibilityLabel("Edited")
                }
                Spacer()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: item.id) { checkSource() }
    }

    private func checkSource() {
        guard let assetID = item.sourceAssetID else {
            sourceAvailable = false
            return
        }
        // Synchronous fetch — fast, in-memory PhotoKit lookup. No network.
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        sourceAvailable = (result.firstObject != nil)
    }
}
