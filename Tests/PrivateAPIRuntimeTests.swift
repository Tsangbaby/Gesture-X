import Foundation
import ObjectiveC

// A macOS executable harness for the actual production PrivateAPI.swift.
// Authored for the next authorized validation stage; not executed on Linux.
@objc(TLRuntimeFixture)
final class RuntimeFixture: NSObject {
    private static let instance = RuntimeFixture()
    var calls = 0

    @objc dynamic class func sharedFixture() -> NSObject { instance }
    @objc dynamic func objectValue() -> NSObject { self }
    @objc dynamic func booleanValue() -> Bool { true }
    @objc dynamic func integerValue() -> Int32 { 7 }
    @objc dynamic func requiresArgument(_ value: Int32) -> Bool {
        calls += 1
        return value != 0
    }
    @objc dynamic func lockShape(_ source: Int32, withOptions options: NSDictionary?) {
        calls += 1
    }
}

private struct TestFailure: Error { let name: String }

@main
struct PrivateAPIRuntimeTests {
    static func main() throws {
        let fixture = RuntimeFixture()
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw TestFailure(name: name) }
            passed += 1
        }
        try check(PrivateAPI.bool(fixture, "booleanValue") == true, "BOOL getter")
        try check(PrivateAPI.object(fixture, "objectValue") === fixture, "plus-zero object ownership")
        try check(PrivateAPI.object(RuntimeFixture.self as AnyObject, "sharedFixture") is RuntimeFixture,
                  "class receiver/metaclass")
        try check(PrivateAPI.bool(fixture, "missingSelector") == nil, "missing selector")
        try check(PrivateAPI.bool(fixture, "integerValue") == nil, "integer is not BOOL")
        try check(PrivateAPI.object(fixture, "booleanValue") == nil, "BOOL is not object")
        try check(PrivateAPI.bool(fixture, "requiresArgument:") == nil, "getter arity mismatch")
        try check(fixture.calls == 0, "rejected methods were not invoked")
        let selector = NSSelectorFromString("lockShape:withOptions:")
        try check(PrivateAPI.checkedMethod(in: RuntimeFixture.self, selector: selector,
                                          returns: "v", arguments: ["i", "@"]) != nil,
                  "fixed Int32/object ABI accepted")
        try check(PrivateAPI.checkedMethod(in: RuntimeFixture.self, selector: selector,
                                          returns: "v", arguments: ["Q", "@"]) == nil,
                  "NSUInteger cannot masquerade as Int32")
        try check(PrivateAPI.checkedMethod(in: RuntimeFixture.self, selector: selector,
                                          returns: "B", arguments: ["i", "@"]) == nil,
                  "return-type mismatch")
        print("PASS: \(passed) production-PrivateAPI runtime checks")
    }
}
