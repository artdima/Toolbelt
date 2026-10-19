import Foundation
import Testing
@testable import ToolbeltCore

@Suite("GitLab text for the model")
struct GitLabFormatterTests {
    private let formatter = GitLabFormatter(timeZone: TimeZone(secondsFromGMT: 3 * 3600)!)

    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    @Test("A failed pipeline: failed trigger first, a downstream that was never created, every job's status")
    func pipeline() throws {
        let pipeline: GitLabPipeline = try decode("""
        {"id": 402513, "status": "failed", "ref": "master", "sha": "8b3c5f0e", "source": "push",
         "created_at": "2026-10-17T09:03:45.123Z", "duration": 723, "user": {"username": "dima"},
         "web_url": "https://gitlab.gftech.ru/growfood/gf_android_app/-/pipelines/402513"}
        """)
        let jobs: [GitLabJob] = try decode("""
        [{"id": 4, "name": "autoTestsPassed", "stage": "autotests", "status": "skipped"},
         {"id": 1, "name": "unitTests", "stage": "test", "status": "success", "duration": 265},
         {"id": 2, "name": "uploadDebug", "stage": "deploy", "status": "success", "duration": 30.4},
         {"id": 3, "name": "autoTestsFailed", "stage": "autotests", "status": "success"}]
        """)
        let bridges: [GitLabBridge] = try decode("""
        [{"id": 5, "name": "trigger_auto_tests", "stage": "autotests", "status": "failed",
          "failure_reason": "downstream_bridge_project_not_found", "downstream_pipeline": null}]
        """)

        let text = formatter.pipeline(pipeline, project: "growfood/gf_android_app", commit: nil, jobs: jobs, bridges: bridges, isComplete: true)
        let entries = text.components(separatedBy: "(listed first):\n")[1].split(separator: "\n").map(String.init)

        #expect(text.hasPrefix("Pipeline #402513 · failed · growfood/gf_android_app\nref master · sha 8b3c5f0e\n"))
        #expect(text.contains("by @dima · source push · created 2026-10-17 12:03+03:00 · duration 12m 3s"))
        #expect(entries[0] == "✗ failed · trigger trigger_auto_tests #5 · stage autotests · failure_reason downstream_bridge_project_not_found · downstream pipeline: not created")
        #expect(entries[1] == "✓ success · job unitTests #1 · stage test · 4m 25s")
        #expect(entries[2] == "✓ success · job uploadDebug #2 · stage deploy · 30s")
        #expect(entries[3] == "✓ success · job autoTestsFailed #3 · stage autotests")
        #expect(entries[4] == "○ skipped · job autoTestsPassed #4 · stage autotests")
        #expect(text.contains("Job pages: https://gitlab.gftech.ru/growfood/gf_android_app/-/jobs/<id>"))
    }

    @Test("A created downstream pipeline is shown with its project")
    func downstream() throws {
        let pipeline: GitLabPipeline = try decode(#"{"id": 1, "status": "success"}"#)
        let bridges: [GitLabBridge] = try decode("""
        [{"id": 9, "name": "deploy", "status": "success",
          "downstream_pipeline": {"id": 77, "status": "running", "web_url": "https://g.example/ops/deploy/-/pipelines/77"}}]
        """)
        let text = formatter.pipeline(pipeline, project: "a/b", commit: nil, jobs: [], bridges: bridges, isComplete: true)
        #expect(text.contains("downstream pipeline #77 running in ops/deploy https://g.example/ops/deploy/-/pipelines/77"))
    }

    @Test("Durations and times")
    func values() {
        #expect(GitLabFormatter.duration(265.4) == "4m 25s")
        #expect(GitLabFormatter.duration(3600) == "1h")
        #expect(GitLabFormatter.duration(3725) == "1h 2m")
        #expect(GitLabFormatter.duration(7) == "7s")
        #expect(GitLabFormatter.duration(nil) == nil)
        #expect(formatter.time("2026-10-17T09:03:45Z") == "2026-10-17 12:03+03:00")
        #expect(formatter.time("2026-10-17T12:03:45.000+03:00") == "2026-10-17 12:03+03:00")
        #expect(formatter.time("not a date") == nil)
    }

    @Test("Changed files carry their line counts, never the diff")
    func mergeRequest() throws {
        let request: GitLabMergeRequest = try decode("""
        {"id": 1, "iid": 12, "title": "Login fixes", "state": "opened", "has_conflicts": true,
         "source_branch": "fix/login", "target_branch": "develop", "description": "Fixes the crash."}
        """)
        let diffs: [GitLabDiff] = try decode("""
        [{"old_path": "a.kt", "new_path": "a.kt", "diff": "@@ -1 +1,2 @@\\n-old\\n+new\\n+more\\n"},
         {"old_path": "b.kt", "new_path": "c.kt", "renamed_file": true, "diff": ""}]
        """)
        let text = formatter.mergeRequest(request, diffs: diffs, isComplete: true)
        #expect(text.contains("state opened · no conflicts") == false)
        #expect(text.contains("has conflicts"))
        #expect(text.contains("Branches: fix/login → develop"))
        #expect(text.contains("Latest pipeline: none"))
        #expect(text.contains("Changed files — 2 (+2 −1):\nM a.kt  +2 −1\nR b.kt → c.kt  +0 −0"))
        #expect(!text.contains("+new"))
    }
}
