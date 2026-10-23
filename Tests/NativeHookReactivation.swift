// Compiled only into the simulator test dylib. Never a Theos source input.
@_cdecl("taplock_test_reactivate")
public func tapLockTestReactivate() {
    TapLockRuntime.activate()
}
