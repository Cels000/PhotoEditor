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
}
