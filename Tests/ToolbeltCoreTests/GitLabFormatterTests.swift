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
         "source_branch": "fix/login", "target_branch": "develop", "description": "Fixes the crash.",
         "user_notes_count": 3}
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
        #expect(text.contains("Comments: 3 — gitlab_merge_request_discussions shows the review threads."))
    }

    @Test("Review threads: unresolved first, each with its file and line; system notes left out")
    func discussions() throws {
        let (request, discussions) = try reviewFixture()
        let text = formatter.discussions(discussions, request: request, status: .all, file: nil, isComplete: true)

        #expect(text.hasPrefix("""
        Discussions on !12 Login fixes
        1 unresolved · 1 resolved · 1 comment · 1 system note left out
        https://g.example/mobile/app/-/merge_requests/12

        Threads and comments — 3, unresolved first:

        ● unresolved · app/Login.kt:40 (removed line) · on an older version of the diff
          https://g.example/mobile/app/-/merge_requests/12#note_103
          @alice · 2026-10-17 13:00+03:00:
            Why force unwrap?

            ```kotlin
            val x = y!!
            ```
          · @bob changed this line in version 2 of the diff · 2026-10-17 13:20+03:00
          @bob · 2026-10-17 13:21+03:00:
            Done

        ✓ resolved by @bob · app/a.kt:12–15
          https://g.example/mobile/app/-/merge_requests/12#note_101
        """))
        #expect(text.contains("○ comment\n  https://g.example/mobile/app/-/merge_requests/12#note_106\n  @carol"))
        #expect(!text.contains("added 1 commit"))
        #expect(text.hasSuffix("Call gitlab_merge_request with file: \"<path>\" to see a file's diff."))
    }

    @Test("Threads narrowed to unresolved ones, or to one file by the end of its path")
    func discussionFilters() throws {
        let (request, discussions) = try reviewFixture()

        let unresolved = formatter.discussions(discussions, request: request, status: .unresolved, file: nil, isComplete: true)
        #expect(unresolved.contains("\nUnresolved threads — 1:\n"))
        #expect(unresolved.contains("app/Login.kt:40"))
        #expect(!unresolved.contains("app/a.kt:12"))
        #expect(!unresolved.contains("LGTM"))

        let onFile = formatter.discussions(discussions, request: request, status: .all, file: "a.kt", isComplete: true)
        #expect(onFile.contains("\nThreads and comments on a.kt — 1:\n"))
        #expect(onFile.contains("✓ resolved by @bob · app/a.kt:12–15"))

        let none = formatter.discussions(discussions, request: request, status: .resolved, file: "app/Login.kt", isComplete: false)
        #expect(none.contains("\nNo resolved threads on app/Login.kt.\n[Only the first pages of discussions were loaded.]"))
    }

    @Test("A note on a whole file or an image has no line")
    func noteLocations() throws {
        let file: GitLabNotePosition = try decode(#"{"position_type": "file", "old_path": "README.md", "new_path": "README.md"}"#)
        let image: GitLabNotePosition = try decode("""
        {"position_type": "image", "old_path": "logo.png", "new_path": "logo.png", "width": 64, "height": 64, "x": 3, "y": 5}
        """)
        #expect(GitLabFormatter.location(file) == "README.md (whole file)")
        #expect(GitLabFormatter.location(image) == "logo.png (image)")
    }

    private func reviewFixture() throws -> (GitLabMergeRequest, [GitLabDiscussion]) {
        let request: GitLabMergeRequest = try decode("""
        {"id": 1, "iid": 12, "title": "Login fixes", "state": "opened",
         "web_url": "https://g.example/mobile/app/-/merge_requests/12",
         "diff_refs": {"base_sha": "aaa", "start_sha": "aaa", "head_sha": "ccc"}}
        """)
        let discussions: [GitLabDiscussion] = try decode("""
        [{"id": "d1", "individual_note": false, "notes": [
           {"id": 101, "type": "DiffNote", "body": "Rename this?", "author": {"username": "alice"},
            "created_at": "2026-10-17T09:00:00Z", "system": false, "resolvable": true, "resolved": true,
            "resolved_by": {"username": "bob"},
            "position": {"position_type": "text", "head_sha": "ccc", "old_path": "app/a.kt", "new_path": "app/a.kt",
              "old_line": null, "new_line": 15,
              "line_range": {"start": {"line_code": "x_12", "type": "new", "old_line": null, "new_line": 12},
                             "end": {"line_code": "x_15", "type": "new", "old_line": null, "new_line": 15}}}}]},
         {"id": "d2", "individual_note": true, "notes": [
           {"id": 102, "type": null, "body": "added 1 commit\\n\\n* 8b3c5f0e - Fix", "author": {"username": "bob"},
            "created_at": "2026-10-17T09:30:00Z", "system": true, "resolvable": false}]},
         {"id": "d3", "individual_note": false, "notes": [
           {"id": 103, "type": "DiffNote", "body": "Why force unwrap?\\n\\n```kotlin\\nval x = y!!\\n```",
            "author": {"username": "alice"}, "created_at": "2026-10-17T10:00:00Z", "system": false,
            "resolvable": true, "resolved": false, "resolved_by": null,
            "position": {"position_type": "text", "head_sha": "bbb", "old_path": "app/Login.kt", "new_path": "app/Login.kt",
              "old_line": 40, "new_line": null, "line_range": null}},
           {"id": 104, "type": null, "author": {"username": "bob"}, "created_at": "2026-10-17T10:20:00Z",
            "body": "changed this line in [version 2 of the diff](/mobile/app/-/merge_requests/12/diffs?diff_id=5#c1)",
            "system": true, "resolvable": false},
           {"id": 105, "type": "DiffNote", "body": "Done", "author": {"username": "bob"},
            "created_at": "2026-10-17T10:21:00Z", "system": false, "resolvable": true, "resolved": false}]},
         {"id": "d4", "individual_note": true, "notes": [
           {"id": 106, "type": null, "body": "LGTM after the fix", "author": {"username": "carol"},
            "created_at": "2026-10-17T11:00:00Z", "system": false, "resolvable": false}]}]
        """)
        return (request, discussions)
    }
}
