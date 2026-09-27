import Foundation
import Testing
@testable import ToolbeltCore

@Suite("User Defaults parsing")
struct UserDefaultsParsingTests {
    @Test("listapps yields the developer's apps, not the system ones")
    func installedAppsFromListapps() throws {
        let output = """
        {
            "com.apple.mobilesafari" =     {
                ApplicationType = System;
                Bundle = "file:///Library/Developer/CoreSimulator/Volumes/iOS_22A3351/Applications/MobileSafari.app/";
                CFBundleDisplayName = Safari;
                CFBundleExecutable = MobileSafari;
                CFBundleIdentifier = "com.apple.mobilesafari";
                CFBundleName = MobileSafari;
                CFBundleVersion = "8619.1.26.4.1";
                DataContainer = "file:///Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Data/Application/1F2E/";
                GroupContainers =         {
                };
                Path = "/Library/Developer/CoreSimulator/Volumes/iOS_22A3351/Applications/MobileSafari.app";
                SBAppTags =         (
                );
            };
            "com.example.counter" =     {
                ApplicationType = User;
                Bundle = "file:///Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Bundle/Application/9C1D/Runner.app/";
                CFBundleDisplayName = Counter;
                CFBundleExecutable = Runner;
                CFBundleIdentifier = "com.example.counter";
                CFBundleName = Runner;
                CFBundleVersion = 1;
                DataContainer = "file:///Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Data/Application/5B7A%20Space/";
                GroupContainers =         {
                    "group.com.example.counter" = "file:///Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Shared/AppGroup/2D3E/";
                };
                Path = "/Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Bundle/Application/9C1D/Runner.app";
                SBAppTags =         (
                );
            };
            "com.example.nameless" =     {
                ApplicationType = User;
                CFBundleIdentifier = "com.example.nameless";
            };
        }
        """

        let apps = UserDefaultsParsing.installedApps(fromListappsOutput: Data(output.utf8))
        let counter = try #require(apps.first { $0.bundleID == "com.example.counter" })

        #expect(apps.map(\.bundleID) == ["com.example.nameless", "com.example.counter"])
        #expect(counter.name == "Counter")
        #expect(counter.title == "Counter · com.example.counter")
        #expect(
            counter.dataContainer
                == "/Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Data/Application/5B7A Space"
        )
        #expect(
            counter.preferencesPlistPath
                == "/Users/me/Library/Developer/CoreSimulator/Devices/AAA-111/data/Containers/Data/Application/5B7A Space/Library/Preferences/com.example.counter.plist"
        )

        let nameless = apps[0]
        #expect(nameless.name == "com.example.nameless")
        #expect(nameless.title == "com.example.nameless")
        #expect(nameless.dataContainer == nil)
        #expect(nameless.preferencesPlistPath == nil)
    }

    @Test("Garbage is not a list of apps")
    func installedAppsFromGarbage() {
        #expect(UserDefaultsParsing.installedApps(fromListappsOutput: Data("not a plist".utf8)).isEmpty)
        #expect(UserDefaultsParsing.installedApps(fromListappsOutput: Data()).isEmpty)
    }

    @Test("An exported domain keeps every plist type apart")
    func entriesFromExportedPlist() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ratio</key>
            <real>0.5</real>
            <key>flutter.onboarded</key>
            <true/>
            <key>flutter.counter</key>
            <integer>3</integer>
            <key>name</key>
            <string>Dmitriy</string>
            <key>lastSync</key>
            <date>2026-09-26T04:00:00Z</date>
            <key>token</key>
            <data>AQID</data>
            <key>tags</key>
            <array>
                <string>a</string>
                <integer>2</integer>
            </array>
            <key>nested</key>
            <dict>
                <key>b</key>
                <false/>
                <key>a</key>
                <string>x</string>
            </dict>
        </dict>
        </plist>
        """

        let entries = try #require(UserDefaultsParsing.entries(fromPlist: Data(plist.utf8)))

        #expect(entries.map(\.key) == [
            "flutter.counter", "flutter.onboarded", "lastSync", "name", "nested", "ratio", "tags", "token"
        ])
        #expect(entries[0].value == .integer(3))
        #expect(entries[1].value == .bool(true))
        #expect(entries[2].value == .date(Date(timeIntervalSince1970: 1_790_395_200)))
        #expect(entries[3].value == .string("Dmitriy"))
        #expect(entries[4].value == .dictionary("{a: \"x\", b: false}", count: 2))
        #expect(entries[5].value == .double(0.5))
        #expect(entries[6].value == .array("[\"a\", 2]", count: 2))
        #expect(entries[7].value == .data(bytes: 3))
    }

    @Test("A whole number stored as a real stays a Double")
    func integralRealStaysDouble() throws {
        let plist = """
        <plist version="1.0"><dict><key>scale</key><real>2</real><key>count</key><integer>1</integer></dict></plist>
        """

        let entries = try #require(UserDefaultsParsing.entries(fromPlist: Data(plist.utf8)))

        #expect(entries.map(\.value) == [.integer(1), .double(2)])
        #expect(entries[1].value.display == "2.0")
    }

    @Test("Not a dictionary, not a domain")
    func entriesFromOtherPlists() {
        let array = """
        <plist version="1.0"><array><string>a</string></array></plist>
        """

        #expect(UserDefaultsParsing.entries(fromPlist: Data(array.utf8)) == nil)
        #expect(UserDefaultsParsing.entries(fromPlist: Data("Domain com.example does not exist".utf8)) == nil)
    }

    @Test("Values are shown and typed for the table")
    func valueDisplay() {
        #expect(UserDefaultsValue.string("hi").display == "hi")
        #expect(UserDefaultsValue.integer(-4).display == "-4")
        #expect(UserDefaultsValue.double(0.25).display == "0.25")
        #expect(UserDefaultsValue.bool(false).display == "false")
        #expect(UserDefaultsValue.data(bytes: 12).display == "12 bytes")
        #expect(UserDefaultsValue.date(Date(timeIntervalSince1970: 0)).display == "1970-01-01T00:00:00Z")
        #expect(UserDefaultsValue.array("[1]", count: 1).typeName == "Array · 1")
        #expect(UserDefaultsValue.dictionary("{}", count: 0).typeName == "Dictionary · 0")
    }

    @Test("An edit keeps the type of the value it replaces")
    func replacingKeepsType() {
        #expect(UserDefaultsValue.integer(3).replacing(with: " 42 ") == .integer(42))
        #expect(UserDefaultsValue.integer(3).replacing(with: "4.2") == nil)
        #expect(UserDefaultsValue.integer(3).replacing(with: "") == nil)
        #expect(UserDefaultsValue.double(0.5).replacing(with: "1") == .double(1))
        #expect(UserDefaultsValue.double(0.5).replacing(with: "one") == nil)
        #expect(UserDefaultsValue.string("a").replacing(with: "") == .string(""))
        #expect(UserDefaultsValue.string("a").replacing(with: " b ") == .string(" b "))
        #expect(UserDefaultsValue.bool(true).replacing(with: "NO") == .bool(false))
        #expect(UserDefaultsValue.bool(true).replacing(with: "maybe") == nil)
        #expect(UserDefaultsValue.data(bytes: 1).replacing(with: "x") == nil)
    }

    @Test("defaults write gets a typed value; collections cannot be written")
    func writeArguments() {
        #expect(UserDefaultsValue.string("hi").writeArguments == ["-string", "hi"])
        #expect(UserDefaultsValue.integer(-1).writeArguments == ["-int", "-1"])
        #expect(UserDefaultsValue.double(0.5).writeArguments == ["-float", "0.5"])
        #expect(UserDefaultsValue.bool(true).writeArguments == ["-bool", "true"])
        #expect(UserDefaultsValue.date(Date()).writeArguments == nil)
        #expect(UserDefaultsValue.array("[]", count: 0).isEditable == false)
        #expect(UserDefaultsValue.string("").isEditable)
    }
}
