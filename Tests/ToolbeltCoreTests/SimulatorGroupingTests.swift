import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Simulator grouping")
struct SimulatorGroupingTests {
    @Test("iOS comes before Android, newer versions first, devices in SDK order")
    func platformsAndVersionsAreOrdered() {
        let groups = SimulatorGroup.grouped([
            device(.android, "Pixel_7_API_34", "API 34"),
            device(.ios, "iPhone 15", "17.5"),
            device(.ios, "iPhone 16 Pro", "18.0"),
            device(.android, "Pixel_8_API_35", "API 35"),
            device(.ios, "iPhone 16", "18.0"),
            device(.ios, "iPhone 17", "26.0")
        ])

        #expect(groups.map(\.title) == ["iOS 26.0", "iOS 18.0", "iOS 17.5", "Android API 35", "Android API 34"])
        #expect(groups[1].devices.map(\.name) == ["iPhone 16 Pro", "iPhone 16"])
    }

    @Test("Codenames follow the numbered versions, an unknown version goes last")
    func unknownVersionGoesLast() {
        let groups = SimulatorGroup.grouped([
            device(.android, "Custom", ""),
            device(.android, "Pixel_7_API_34", "API 34"),
            device(.android, "Preview", "API Baklava")
        ])

        #expect(groups.map(\.title) == ["Android API 34", "Android API Baklava", "Android"])
    }

    @Test("Search keeps the whole group when its title matches, otherwise matching devices")
    func searchMatchesTitleOrName() {
        let group = SimulatorGroup.grouped([
            device(.ios, "iPhone 16 Pro", "18.0"),
            device(.ios, "iPad Air", "18.0")
        ])[0]

        #expect(group.matching("ios 18")?.devices.count == 2)
        #expect(group.matching("ipad")?.devices.map(\.name) == ["iPad Air"])
        #expect(group.matching("pixel") == nil)
    }

    private func device(_ platform: MobilePlatform, _ name: String, _ osVersion: String) -> SimulatorDevice {
        SimulatorDevice(
            platform: platform,
            identifier: name,
            name: name,
            osVersion: osVersion,
            state: .shutdown,
            serial: nil
        )
    }
}
