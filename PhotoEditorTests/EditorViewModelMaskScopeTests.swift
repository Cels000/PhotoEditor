// PhotoEditorTests/EditorViewModelMaskScopeTests.swift
import XCTest
@testable import PhotoEditor

@MainActor
final class EditorViewModelMaskScopeTests: XCTestCase {

    func testUnmaskedMode_writesGoToBothStacks() {
        let vm = EditorViewModel()
        vm.document.mask = nil
        var s = vm.stack
        s.light.exposure = 0.5
        vm.stack = s
        XCTAssertEqual(vm.document.subjectStack.light.exposure, 0.5)
        XCTAssertEqual(vm.document.backgroundStack.light.exposure, 0.5)
    }

    func testMaskedSubjectScope_writesOnlyToSubject() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.activeScope = .subject
        var s = vm.stack
        s.light.exposure = 0.5
        vm.stack = s
        XCTAssertEqual(vm.document.subjectStack.light.exposure, 0.5)
        XCTAssertEqual(vm.document.backgroundStack.light.exposure, 0)
    }

    func testMaskedBackgroundScope_writesOnlyToBackground() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.activeScope = .background
        var s = vm.stack
        s.color.temperature = -0.4
        vm.stack = s
        XCTAssertEqual(vm.document.backgroundStack.color.temperature, -0.4)
        XCTAssertEqual(vm.document.subjectStack.color.temperature, 0)
    }

    func testMaskedFullScope_mirrorWrites() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.activeScope = .full
        var s = vm.stack
        s.color.saturation = 0.3
        vm.stack = s
        XCTAssertEqual(vm.document.subjectStack.color.saturation, 0.3)
        XCTAssertEqual(vm.document.backgroundStack.color.saturation, 0.3)
    }

    func testCropMirrorInvariant_acrossAllScopes() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()

        for scope in [MaskScope.subject, .background, .full] {
            vm.activeScope = scope
            var s = vm.stack
            s.crop.normalizedRect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
            vm.stack = s
            XCTAssertEqual(vm.document.subjectStack.crop, vm.document.backgroundStack.crop,
                          "crop diverged in scope \(scope)")
        }
    }

    func testCropMirrorInvariant_unmaskedMode() {
        let vm = EditorViewModel()
        vm.document.mask = nil
        var s = vm.stack
        s.crop.normalizedRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        vm.stack = s
        XCTAssertEqual(vm.document.subjectStack.crop, vm.document.backgroundStack.crop)
    }

    // MARK: - Lifecycle

    func testRemoveMask_collapsesToSubjectStack() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask(feather: 0.5)
        vm.document.subjectStack.light.exposure = 0.4
        vm.document.backgroundStack.light.exposure = -0.4

        vm.removeMask()

        XCTAssertNil(vm.document.mask)
        XCTAssertEqual(vm.document.backgroundStack, vm.document.subjectStack)
        XCTAssertEqual(vm.activeScope, .subject)
    }

    func testRemoveMask_whenNoMask_isNoop() {
        let vm = EditorViewModel()
        vm.document.mask = nil
        vm.removeMask()
        XCTAssertNil(vm.document.mask)
    }

    func testToggleInstanceExcluded_addsAndRemoves() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.toggleInstanceExcluded(0)
        XCTAssertTrue(vm.document.mask!.excludedInstances.contains(0))
        vm.toggleInstanceExcluded(0)
        XCTAssertFalse(vm.document.mask!.excludedInstances.contains(0))
    }

    func testFeatherClamped_to0to1() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.updateMaskFeather(2.0)
        XCTAssertEqual(vm.document.mask?.feather, 1.0)
        vm.updateMaskFeather(-0.3)
        XCTAssertEqual(vm.document.mask?.feather, 0.0)
        vm.updateMaskFeather(0.7)
        XCTAssertEqual(vm.document.mask?.feather, 0.7)
    }

    func testFeather_whenNoMask_isNoop() {
        let vm = EditorViewModel()
        vm.document.mask = nil
        vm.updateMaskFeather(0.5)
        XCTAssertNil(vm.document.mask)
    }

    func testInvertToggle_setsField() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.setMaskInvert(true)
        XCTAssertEqual(vm.document.mask?.invert, true)
        vm.setMaskInvert(false)
        XCTAssertEqual(vm.document.mask?.invert, false)
    }

    func testCanApplyMask_falseWithoutPhoto() {
        let vm = EditorViewModel()
        XCTAssertFalse(vm.canApplyMask)
    }
}
