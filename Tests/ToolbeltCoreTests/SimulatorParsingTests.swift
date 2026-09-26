import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Simulator list parsing")
struct SimulatorParsingTests {
    @Test("Simulators from simctl JSON carry their state")
    func simulatorsCarryState() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "AAA-111", "name": "iPhone 16 Pro", "state": "Booted", "isAvailable": true },
              { "udid": "BBB-222", "name": "iPhone 16", "state": "Shutdown", "isAvailable": true }
            ]
          }
        }
        """

        let devices = SimulatorParsing.simulators(fromSimctlJSON: Data(json.utf8))

        #expect(devices.count == 2)
        #expect(devices[0].identifier == "AAA-111")
        #expect(devices[0].state == .booted)
        #expect(devices[0].osVersion == "18.0")
        #expect(devices[1].state == .shutdown)
        #expect(devices[1].platform == .ios)
    }

    @Test("Runtimes marked unavailable are dropped")
    func unavailableDevicesAreDropped() {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-14-0": [
              { "udid": "CCC-333", "name": "iPhone 8", "state": "Shutdown", "isAvailable": false }
            ]
          }
        }
        """

        #expect(SimulatorParsing.simulators(fromSimctlJSON: Data(json.utf8)).isEmpty)
    }

    @Test("Runtimes of other platforms are skipped")
    func otherPlatformsAreSkipped() {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.watchOS-11-2": [
              { "udid": "DDD-444", "name": "Apple Watch Series 10", "state": "Shutdown", "isAvailable": true }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "AAA-111", "name": "iPhone 16", "state": "Shutdown", "isAvailable": true }
            ]
          }
        }
        """

        #expect(SimulatorParsing.simulators(fromSimctlJSON: Data(json.utf8)).map(\.identifier) == ["AAA-111"])
    }

    @Test("A runtime identifier splits into platform and version")
    func runtimeIsSplit() {
        let ios = SimulatorParsing.runtime("com.apple.CoreSimulator.SimRuntime.iOS-18-0")
        #expect(ios.platform == "iOS")
        #expect(ios.version == "18.0")

        let watch = SimulatorParsing.runtime("com.apple.CoreSimulator.SimRuntime.watchOS-11-2")
        #expect(watch.platform == "watchOS")
        #expect(watch.version == "11.2")

        #expect(SimulatorParsing.runtime("iOS").version.isEmpty)
    }

    @Test("The API level comes from the AVD's target or its system image")
    func androidAPILevel() {
        let ini = """
        avd.ini.encoding=UTF-8
        path=/Users/me/.android/avd/Pixel_7_API_34.avd
        target=android-34
        """
        #expect(SimulatorParsing.androidAPILevel(fromAvdIni: ini) == "34")

        let config = """
        AvdId=Pixel_8_API_35
        image.sysdir.1=system-images/android-35/google_apis_playstore/arm64-v8a/
        tag.id=google_apis_playstore
        """
        #expect(SimulatorParsing.androidAPILevel(fromAvdIni: config) == "35")

        #expect(SimulatorParsing.androidAPILevel(fromAvdIni: "hw.lcd.density=420") == nil)
    }

    @Test("AVD names ignore the emulator's own chatter")
    func avdNamesSkipLogLines() {
        let output = """
        INFO    | Storing crashdata in: /tmp/AndroidEmulator/emu-crash.db
        Pixel_7_API_34
        Medium_Phone_API_36

        """

        #expect(SimulatorParsing.avdNames(fromEmulatorOutput: output) == ["Pixel_7_API_34", "Medium_Phone_API_36"])
    }

    @Test("Only emulators in state device count as running")
    func runningSerials() {
        let output = """
        List of devices attached
        emulator-5554\tdevice
        emulator-5556\toffline
        R5CT30ABCDE\tdevice
        """

        #expect(SimulatorParsing.runningEmulatorSerials(fromAdbOutput: output) == ["emulator-5554"])
    }

    @Test("adb emu avd name drops the trailing OK")
    func avdNameFromEmuOutput() {
        #expect(SimulatorParsing.avdName(fromEmuOutput: "Pixel_7_API_34\r\nOK\r\n") == "Pixel_7_API_34")
        #expect(SimulatorParsing.avdName(fromEmuOutput: "OK\r\n") == nil)
    }

    @Test("A crash log is cut down to its tail")
    func lastLinesOfLog() {
        let log = (1 ... 12).map { "line \($0)" }.joined(separator: "\n")

        #expect(SimulatorParsing.lastLines(log, limit: 3) == "line 10\nline 11\nline 12")
    }
}
