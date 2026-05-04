// SubjectMaskStore.swift
// PhotoEditor
//
// Vision-backed subject mask compute with in-memory caching.
// One actor instance per app session; injected into RenderEngine + EditorViewModel.

import CoreImage
import Foundation
import Vision

typealias AssetID = String

struct SubjectMaskResult: Equatable {
    let combined: CIImage
    let perInstance: [CIImage]
    let instanceCount: Int
    let detectedAt: Date

    static func == (lhs: SubjectMaskResult, rhs: SubjectMaskResult) -> Bool {
        lhs.detectedAt == rhs.detectedAt && lhs.instanceCount == rhs.instanceCount
    }
}

protocol SubjectMaskProvider: AnyObject {
    func currentMask(for assetID: AssetID) -> SubjectMaskResult?
}

enum SubjectMaskError: Error {
    case visionFailed(Error)
    case noObservations
}

@MainActor
final class SubjectMaskStore: SubjectMaskProvider {

    private struct CacheEntry {
        let result: SubjectMaskResult
    }

    private var cache: [AssetID: CacheEntry] = [:]
    private var inflight: [AssetID: Task<SubjectMaskResult, Error>] = [:]

    private let visionContext: CIContext

    init() {
        self.visionContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Test-only constructor; identical for now but reserved for stubbing.
    static func makeForTesting() -> SubjectMaskStore {
        SubjectMaskStore()
    }

    /// Synchronous read of the most recently cached mask. Called from PipelineBuilder
    /// (potentially off-main during rendering); reads from main-actor-isolated cache.
    nonisolated func currentMask(for assetID: AssetID) -> SubjectMaskResult? {
        return MainActor.assumeIsolated {
            cache[assetID]?.result
        }
    }

    func mask(for assetID: AssetID, source: CIImage) async throws -> SubjectMaskResult {
        if let cached = cache[assetID]?.result {
            return cached
        }
        if let task = inflight[assetID] {
            return try await task.value
        }

        let task = Task<SubjectMaskResult, Error> { [weak self] in
            guard let self else { throw SubjectMaskError.noObservations }
            return try await self.compute(source: source)
        }
        inflight[assetID] = task
        defer { inflight[assetID] = nil }

        let result = try await task.value
        cache[assetID] = CacheEntry(result: result)
        return result
    }

    func prefetch(for assetID: AssetID, source: CIImage) {
        guard cache[assetID] == nil, inflight[assetID] == nil else { return }
        Task { [weak self] in
            _ = try? await self?.mask(for: assetID, source: source)
        }
    }

    func clear(for assetID: AssetID) {
        cache[assetID] = nil
        inflight[assetID]?.cancel()
        inflight[assetID] = nil
    }

    // MARK: - Vision compute

    private func compute(source: CIImage) async throws -> SubjectMaskResult {
        let detached: Task<SubjectMaskResult, Error> = Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: source, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw SubjectMaskError.visionFailed(error)
            }

            guard let observation = request.results?.first as? VNInstanceMaskObservation else {
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
