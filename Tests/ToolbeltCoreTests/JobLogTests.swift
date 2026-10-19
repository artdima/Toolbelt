import Foundation
import Testing
@testable import ToolbeltCore

@Suite("GitLab job log")
struct JobLogTests {
    private let esc = "\u{1B}"

    @Test("Colors, section markers and progress overwrites are gone")
    func cleaning() {
        let raw = """
        \(esc)[0KRunning with gitlab-runner 17.4.0\(esc)[0;m
        section_start:1729000000:prepare_executor[collapsed=true]\r\(esc)[0K\(esc)[0K\(esc)[36;1mPreparing the "docker" executor\(esc)[0;m
        Downloading 10%\rDownloading 50%\rDownloading 100%
        section_end:1729000010:prepare_executor\r\(esc)[0K
        \(esc)[1m\(esc)[32mBUILD SUCCESSFUL\(esc)[0m\(esc)[0m in 4m 25s\r
        section_end:1729000275:step_script\r\(esc)[0K\(esc)[0Ksection_start:1729000275:cleanup\r\(esc)[0K\(esc)[0K\(esc)[36;1mCleaning up\(esc)[0;m
        \(esc)]8;;https://example.com\u{07}a link\(esc)]8;;\u{07}

        """

        #expect(JobLog.cleanLines(raw) == [
            "Running with gitlab-runner 17.4.0",
            "Preparing the \"docker\" executor",
            "Downloading 100%",
            "BUILD SUCCESSFUL in 4m 25s",
            "Cleaning up",
            "a link"
        ])
    }

    @Test("Blank lines inside the log survive, trailing ones do not")
    func blankLines() {
        #expect(JobLog.cleanLines("a\n\nb\n\n\n") == ["a", "", "b"])
        #expect(JobLog.cleanLines("") == [])
    }

    @Test("Tail returns the last lines and says which ones")
    func tail() {
        let lines = (1...10).map { "line \($0)" }
        let result = JobLog.tail(lines, count: 3)
        #expect(result.header == "Lines 8–10 of 10:")
        #expect(result.body == "line 8\nline 9\nline 10")
        #expect(JobLog.tail(lines, count: 50).header == "All 10 lines of the log:")
    }

    @Test("Grep numbers matches and context like grep -n, with gaps")
    func grep() throws {
        let lines = (1...20).map { $0 == 5 || $0 == 6 || $0 == 15 ? "BUILD FAILED \($0)" : "noise \($0)" }
        let result = try JobLog.grep(lines, pattern: "BUILD (SUCCESSFUL|FAILED)", context: 1)

        #expect(result.header == "3 of 20 lines match /BUILD (SUCCESSFUL|FAILED)/, with 1 lines of context:")
        #expect(result.body == """
         4-noise 4
         5:BUILD FAILED 5
         6:BUILD FAILED 6
         7-noise 7
        --
        14-noise 14
        15:BUILD FAILED 15
        16-noise 16
        """)
    }

    @Test("No match and a broken pattern are told apart")
    func grepEdges() throws {
        let none = try JobLog.grep(["a", "b"], pattern: "zzz", context: 3)
        #expect(none.body.isEmpty)
        #expect(none.header.hasPrefix("No line of 2 matches"))
        #expect(throws: JobLogError.invalidPattern("(")) {
            try JobLog.grep(["a"], pattern: "(", context: 0)
        }
    }
}
