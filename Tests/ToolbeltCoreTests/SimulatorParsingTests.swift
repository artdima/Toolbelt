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
        #expect(devices[0].detail == "iOS 18.0")
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

    @Test("A runtime identifier turns into a readable name")
    func runtimeTitleIsReadable() {
        #expect(SimulatorParsing.runtimeTitle("com.apple.CoreSimulator.SimRuntime.iOS-18-0") == "iOS 18.0")
        #expect(SimulatorParsing.runtimeTitle("com.apple.CoreSimulator.SimRuntime.watchOS-11-2") == "watchOS 11.2")
        #expect(SimulatorParsing.runtimeTitle("iOS") == "iOS")
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
