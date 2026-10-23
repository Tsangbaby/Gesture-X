import Foundation
import ObjectiveC
import Darwin

// OS receivers only are fixtures. Compile unchanged production AppAction and
// ABI checker; this is NOT an iOS 15 SpringBoard launch or freeze-repair test.
enum NativeLaunchBoundary {
    static var launchServicesCalls = 0
    static var inheritedClientCalls = 0
    static var singletonCalls = 0
}

@objc(TLNativeProxyFixture)
class NativeProxyFixture: NSObject {
    @objc class func applicationProxyForIdentifier(_ identifier: NSString) -> NSObject? {
        NativeLaunchBoundary.launchServicesCalls += 1
        return nil
    }
}

@objc(TLNativeWorkspaceFixture)
class NativeWorkspaceFixture: NSObject {
    @objc class func defaultWorkspace() -> NSObject? {
        NativeLaunchBoundary.launchServicesCalls += 1
        return nil
    }
}

@objc(TLNativeRecordFixture)
class NativeRecordFixture: NSObject {}

@objc(TLNativeUIApplicationFixture)
class NativeUIApplicationFixture: NSObject {
    static var current: NSObject?
    @objc class func sharedApplication() -> NSObject? {
        NativeLaunchBoundary.singletonCalls += 1
        return current
    }
}

@objc(TLNativeSpringBoardFixture)
class NativeSpringBoardFixture: NativeUIApplicationFixture {}

class WorkingNativeSpringBoardFixture: NativeSpringBoardFixture {
    var identifiers: [String] = []
    var suspendedValues: [Bool] = []
    var result = true
    @objc func launchApplicationWithIdentifier(_ identifier: NSString, suspended: Bool) -> Bool {
        identifiers.append(identifier as String)
        suspendedValues.append(suspended)
        return result
    }
}

class WrongReturnNativeFixture: NativeSpringBoardFixture {
    var calls = 0
    @objc func launchApplicationWithIdentifier(_ identifier: NSString, suspended: Bool) -> Int64 {
        calls += 1
        return 1
    }
}

class WrongIdentifierNativeFixture: NativeSpringBoardFixture {
    var calls = 0
    @objc func launchApplicationWithIdentifier(_ identifier: Int32, suspended: Bool) -> Bool {
        calls += 1
        return true
    }
}

class WrongSuspendedNativeFixture: NativeSpringBoardFixture {
    var calls = 0
    @objc func launchApplicationWithIdentifier(_ identifier: NSString, suspended: Int32) -> Bool {
        calls += 1
        return true
    }
}

private let inheritedClientLaunch: @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool = {
    _, _, _, _ in
    NativeLaunchBoundary.inheritedClientCalls += 1
    return true
}

@main
struct NativeAppRuntimeTests {
    static var assertions = 0
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("NATIVE_APP_RUNTIME_FAIL: \(message)")
            fflush(stdout)
            exit(1)
        }
        assertions += 1
    }

    static func main() {
        // Model UIApplication's inherited client method without adding that
        // method to the SpringBoard class itself. Never accept that fallback.
        let selector = NSSelectorFromString("launchApplicationWithIdentifier:suspended:")
        require(class_addMethod(NativeUIApplicationFixture.self, selector,
                    unsafeBitCast(inheritedClientLaunch, to: IMP.self), "B@:@B"),
                "could not establish inherited UIKit client method fixture")
        let working = WorkingNativeSpringBoardFixture()
        NativeUIApplicationFixture.current = working
        let result = AppAction.open(identifier: "com.example.chat")
        require(NativeLaunchBoundary.launchServicesCalls == 0, "SpringBoard action touched LaunchServices")
        require(result, "valid native request did not return the native result")
        require(working.identifiers == ["com.example.chat"] && working.suspendedValues == [false],
                "native method must receive exact Bundle ID once, suspended=false")
        require(NativeLaunchBoundary.inheritedClientCalls == 0, "inherited UIKit launcher was invoked")

        working.result = false
        require(!AppAction.open(identifier: "com.example.chat"), "native rejection reported success")
        require(working.identifiers == ["com.example.chat", "com.example.chat"],
                "native rejection retried or failed to call once")
        let singletonCalls = NativeLaunchBoundary.singletonCalls
        for identifier in ["", ".app", "com..app", "bad/id", "https://app", "com.app\n"] {
            require(!AppAction.open(identifier: identifier), "malformed identifier reached native entry")
        }
        require(NativeLaunchBoundary.singletonCalls == singletonCalls && working.identifiers.count == 2,
                "invalid input queried singleton or launched")

        let wrongReturn = WrongReturnNativeFixture()
        let wrongIdentifier = WrongIdentifierNativeFixture()
        let wrongSuspended = WrongSuspendedNativeFixture()
        for receiver in [wrongReturn, wrongIdentifier, wrongSuspended,
                         NativeSpringBoardFixture(), NSObject()] as [NSObject] {
            NativeUIApplicationFixture.current = receiver
            require(!AppAction.open(identifier: "com.example.chat"),
                    "wrong ABI/identity or inherited-only method was accepted")
        }
        require(wrongReturn.calls == 0 && wrongIdentifier.calls == 0 && wrongSuspended.calls == 0,
                "incompatible native IMP was invoked")
        require(NativeLaunchBoundary.inheritedClientCalls == 0,
                "missing SpringBoard implementation fell through to UIKit client")
        NativeUIApplicationFixture.current = nil
        require(!AppAction.open(identifier: "com.example.chat"), "missing singleton was accepted")

        NativeUIApplicationFixture.current = working
        let beforeOffMain = NativeLaunchBoundary.singletonCalls
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = AppAction.open(identifier: "com.example.chat")
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main fixture did not complete")
        require(NativeLaunchBoundary.singletonCalls == beforeOffMain && working.identifiers.count == 2,
                "off-main request reached singleton/native entry")
        require(NativeLaunchBoundary.launchServicesCalls == 0 && NativeLaunchBoundary.inheritedClientCalls == 0,
                "forbidden launch boundary was touched")
        print("NATIVE_APP_RUNTIME_PASS: \(assertions) assertions; exact production Swift, receiver/ABI fixtures only; NOT device proof")
    }
}
