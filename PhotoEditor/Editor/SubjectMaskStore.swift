// PhotoEditor/Editor/SubjectMaskStore.swift
//
// Vision-backed subject mask compute with in-memory caching.
// One instance per app session, owned by EditorViewModel.
//
// Note on concurrency: this class is @MainActor-isolated. Callers obtain a
// SubjectMaskResult synchronously via cachedMask(for:) and pass it through
// to the render engine as data. PipelineBuilder never reaches back into the
// store, so there's no cross-actor coupling at render time.

import CoreImage
import Foundation
import Vision

typealias AssetID = String

struct SubjectMaskResult: Equatable {
    let combined: CIImage
    let perInstance: [CIImage]
    let instanceCount: Int
    let detectedAt: Date

    /// Equality compares only metadata (when computed, how many instances).
    /// Two masks with different pixels but same instanceCount/detectedAt are equal.
    /// Intended for cache identity, not pixel-equality.
    static func == (lhs: SubjectMaskResult, rhs: SubjectMaskResult) -> Bool {
        lhs.detectedAt == rhs.detectedAt && lhs.instanceCount == rhs.instanceCount
    }
}

enum SubjectMaskError: Error {
    case visionFailed(Error)
    case noObservations
}

@MainActor
final class SubjectMaskStore {

    private struct CacheEntry {
        let result: SubjectMaskResult
    }

    private var cache: [AssetID: CacheEntry] = [:]
    private var inflight: [AssetID: Task<SubjectMaskResult, Error>] = [:]

    init() {}

    /// Test-only constructor; reserved for stubbing.
    static func makeForTesting() -> SubjectMaskStore {
        SubjectMaskStore()
    }

    /// Synchronous read of the most recently cached mask. Safe because the store
    /// is @MainActor-isolated and callers (view models) are also @MainActor.
    func cachedMask(for assetID: AssetID) -> SubjectMaskResult? {
        cache[assetID]?.result
    }

    /// Compute or return cached mask for an asset.
    func mask(for assetID: AssetID, source: CIImage) async throws -> SubjectMaskResult {
        if let cached = cache[assetID]?.result {
            return cached
        }
        if let task = inflight[assetID] {
            return try await task.value
        }

        let task = Task<SubjectMaskResult, Error> {
            try await Self.compute(source: source, priority: .userInitiated)
        }
        inflight[assetID] = task
        defer { inflight[assetID] = nil }

        let result = try await task.value
        cache[assetID] = CacheEntry(result: result)
        return result
    }

    /// Fire-and-forget prefetch (utility QoS).
    func prefetch(for assetID: AssetID, source: CIImage) {
        guard cache[assetID] == nil, inflight[assetID] == nil else { return }
        let task = Task<SubjectMaskResult, Error> {
            try await Self.compute(source: source, priority: .utility)
        }
        inflight[assetID] = task
        Task { [weak self] in
            do {
                let result = try await task.value
                self?.cache[assetID] = CacheEntry(result: result)
            } catch {
                // Prefetch failures are silent; user-initiated path will retry.
            }
            self?.inflight[assetID] = nil
        }
    }

    func clear(for assetID: AssetID) {
        cache[assetID] = nil
        inflight[assetID]?.cancel()
        inflight[assetID] = nil
    }

    // MARK: - Vision compute (off-actor, side-effect-free)

    private static func compute(source: CIImage, priority: TaskPriority) async throws -> SubjectMaskResult {
        let detached: Task<SubjectMaskResult, Error> = Task.detached(priority: priority) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: source, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw SubjectMaskError.visionFailed(error)
            }

            guard let observation = request.results?.first as? VNInstanceMaskObservation else {
                // No foreground detected: black mask (will composite to background only).
                // EditorViewModel surfaces a "No subject detected" toast and prevents enabling the mask in this case.
                let empty = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
                    .cropped(to: source.extent)
                return SubjectMaskResult(combined: empty, perInstance: [],
                                         instanceCount: 0, detectedAt: Date())
            }

            // Combined mask covering all instances.
            let combinedPixelBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let combinedCI = CIImage(cvPixelBuffer: combinedPixelBuffer)

            // Per-instance masks for the refinement-sheet picker.
            var perInstance: [CIImage] = []
            for index in observation.allInstances {
                if let buf = try? observation.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: index),
                    from: handler
                ) {
                    perInstance.append(CIImage(cvPixelBuffer: buf))
                }
            }

            return SubjectMaskResult(
                combined: combinedCI,
                perInstance: perInstance,
                instanceCount: observation.allInstances.count,
                detectedAt: Date()
            )
        }
        return try await detached.value
    }
}
