import Foundation
import CoreFoundation
import ObjectiveC
import Darwin

// Only the OS service objects are fixtures. Compile the actual production
// preference reader/writer, ABI gate, catalog/filter and launch implementation.
@objc(TLTapLockApplicationProxyFixture)
class ApplicationProxyFixture: NSObject {
    static var records: [String: NSObject] = [:]
    @objc class func applicationProxyForIdentifier(_ identifier: NSString) -> NSObject? {
        records[identifier as String]
    }
}

class InstalledProxyFixture: ApplicationProxyFixture {
    let identifier: String
    let name: String
    var installed = true
    var prohibited = false
    var tags: [String] = []
    var category = "User"
    init(_ identifier: String, _ name: String) {
        self.identifier = identifier
        self.name = name
        super.init()
    }
    @objc func bundleIdentifier() -> NSString { identifier as NSString }
    @objc func localizedName() -> NSString { name as NSString }
    @objc func applicationType() -> NSString { category as NSString }
    @objc func isInstalled() -> Bool { installed }
    @objc func isLaunchProhibited() -> Bool { prohibited }
    @objc func appTags() -> NSArray { tags as NSArray }
}

class WrongInstalledABIFixture: ApplicationProxyFixture {
    var calls = 0
    @objc func isInstalled() -> Int64 { calls += 1; return 1 }
}

@objc(TLTapLockApplicationWorkspaceFixture)
class ApplicationWorkspaceFixture: NSObject {
    static var current: NSObject?
    var proxies: [NSObject] = []
    var enumerations = 0
    var launches: [String] = []
    @objc class func defaultWorkspace() -> NSObject? { current }
    @objc func allApplications() -> NSArray { enumerations += 1; return proxies as NSArray }
}

class WorkingWorkspaceFixture: ApplicationWorkspaceFixture {
    var result = true
    @objc func openApplicationWithBundleID(_ identifier: NSString) -> Bool {
        launches.append(identifier as String)
        return result
    }
}

class WrongReturnWorkspaceFixture: ApplicationWorkspaceFixture {
    @objc func openApplicationWithBundleID(_ identifier: NSString) -> Int64 {
        launches.append(identifier as String)
        return 1
    }
}

class WrongArgumentWorkspaceFixture: ApplicationWorkspaceFixture {
    @objc func openApplicationWithBundleID(_ identifier: Int32) -> Bool {
        launches.append("wrong argument invoked")
        return true
    }
}

@main
struct ApplicationsRuntimeTests {
    static var assertions = 0
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("OPEN_APP_RUNTIME_FAIL: \(message)")
            fflush(stdout)
            exit(1)
        }
        assertions += 1
    }

    static func rawAction(_ value: CFPropertyList?) {
        CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, value,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost), "fixture preference write failed")
    }

    static func main() {
        let original = CFPreferencesCopyValue(TapLockPreferences.actionKey as CFString,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        defer { rawAction(original) }
        rawAction(nil)
        require(TapLockPreferences.readAction() == .lock, "upgrade must retain lock when key is absent")
        let enabled = TapLockPreferences.readEnabled()
        require(TapLockPreferences.writeAction(.openApp("com.example.chat")), "App choice could not persist")
        require(TapLockPreferences.readAction() == .openApp("com.example.chat"), "App selection did not round-trip")
        require(TapLockPreferences.readEnabled() == enabled, "selecting an action changed the existing switch")
        require(!TapLockPreferences.writeAction(.unavailable), "invalid action was written")
        for identifier in ["", ".app", "com..app", "com.app.", "com.app/path", "https://app", "com.app\n", String(repeating: "a", count: 256)] {
            require(!TapLockPreferences.writeAction(.openApp(identifier)), "malformed Bundle ID accepted")
            require(TapLockPreferences.readAction() == .openApp("com.example.chat"), "rejected write changed prior selection")
        }
        let malformed: [CFPropertyList] = [
            "openApp" as CFString, kCFBooleanTrue!, [] as CFArray,
            [:] as CFDictionary, ["kind": "unknown"] as CFDictionary,
            ["kind": "openApp"] as CFDictionary,
            ["kind": "openApp", "bundleIdentifier": ""] as CFDictionary,
            ["kind": "openApp", "bundleIdentifier": 123] as CFDictionary,
            ["kind": "lock", "bundleIdentifier": "com.example.chat"] as CFDictionary
        ]
        for value in malformed {
            rawAction(value)
            require(TapLockPreferences.readAction() == .unavailable, "malformed record must not silently lock")
        }
        require(TapLockPreferences.writeAction(.lock) && TapLockPreferences.readAction() == .lock,
                "lock could not be explicitly restored")

        let chat = InstalledProxyFixture("com.example.chat", "B Chat")
        let settings = InstalledProxyFixture("com.apple.Preferences", "A Settings")
        settings.category = "System"
        let removed = InstalledProxyFixture("com.example.removed", "Removed"); removed.installed = false
        let blocked = InstalledProxyFixture("com.example.blocked", "Blocked"); blocked.prohibited = true
        let hidden = InstalledProxyFixture("com.example.hidden", "Hidden"); hidden.tags = ["hidden"]
        let plugin = InstalledProxyFixture("com.example.plugin", "Plugin"); plugin.category = "Plugin"
        let badABI = WrongInstalledABIFixture()
        let workspace = WorkingWorkspaceFixture()
        workspace.proxies = [chat, settings, chat, removed, blocked, hidden, plugin, badABI, NSObject()]
        ApplicationProxyFixture.records = [chat.identifier: chat, settings.identifier: settings,
            removed.identifier: removed, blocked.identifier: blocked, hidden.identifier: hidden,
            plugin.identifier: plugin, "com.example.bad": badABI]
        ApplicationWorkspaceFixture.current = workspace
        require(InstalledApplications.choices() == [
            .init(identifier: settings.identifier, name: settings.name),
            .init(identifier: chat.identifier, name: chat.name)], "filter, sort or deduplication failed")
        require(workspace.enumerations == 1, "catalog enumerated more than once per snapshot")
        require(badABI.calls == 0, "wrong BOOL ABI was invoked")
        require(InstalledApplications.choice(identifier: chat.identifier)?.name == chat.name,
                "selected App name lookup failed")
        require(workspace.enumerations == 1, "name lookup rescanned all applications")
        require(InstalledApplications.open(identifier: chat.identifier), "valid App did not launch")
        require(workspace.launches == [chat.identifier], "launch must pass the exact Bundle ID once")
        workspace.result = false
        require(!InstalledApplications.open(identifier: chat.identifier), "launch failure reported success")
        require(workspace.launches == [chat.identifier, chat.identifier], "failed launch retried")
        for identifier in [removed.identifier, blocked.identifier, hidden.identifier, plugin.identifier,
                           "com.example.missing", "com.example.bad", "bad/id"] {
            require(!InstalledApplications.open(identifier: identifier), "unavailable App was launched")
        }
        require(workspace.launches.count == 2, "unavailable target reached the launch service")
        ApplicationProxyFixture.records[chat.identifier] = settings
        require(!InstalledApplications.open(identifier: chat.identifier), "lookup returned a different App identity")
        ApplicationProxyFixture.records[chat.identifier] = chat
        for incompatible in [ApplicationWorkspaceFixture(), WrongReturnWorkspaceFixture(), WrongArgumentWorkspaceFixture()] {
            ApplicationWorkspaceFixture.current = incompatible
            require(!InstalledApplications.open(identifier: chat.identifier), "missing/wrong ABI was accepted")
            require(incompatible.launches.isEmpty, "incompatible launch method was invoked")
        }
        ApplicationWorkspaceFixture.current = NSObject()
        require(InstalledApplications.choices().isEmpty && !InstalledApplications.open(identifier: chat.identifier),
                "wrong workspace identity was accepted")
        ApplicationWorkspaceFixture.current = nil
        require(InstalledApplications.choices().isEmpty && !InstalledApplications.open(identifier: chat.identifier),
                "missing workspace was accepted")
        ApplicationWorkspaceFixture.current = workspace
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = InstalledApplications.open(identifier: chat.identifier)
            done.signal()
        }
        require(done.wait(timeout: .now() + 5) == .success, "off-main test timed out")
        require(workspace.launches.count == 2, "off-main launch was invoked")
        print("OPEN_APP_RUNTIME_PASS: \(assertions) assertions against production Swift; OS services are fixtures, NOT device launch proof")
    }
}
