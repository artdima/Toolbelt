import Foundation
import Testing
@testable import ToolbeltCore

@Suite("GitLab links")
struct GitLabLinkTests {
    private func parse(_ string: String, basePath: String = "") -> GitLabLink? {
        URL(string: string).flatMap { GitLabLinkParser.parse($0, basePath: basePath) }
    }

    @Test("Pipelines, jobs, merge requests and commits")
    func targets() {
        #expect(parse("https://gitlab.gftech.ru/growfood/gf_android_app/-/pipelines/402513")
            == GitLabLink(host: "gitlab.gftech.ru", projectPath: "growfood/gf_android_app", target: .pipeline(402513)))
        #expect(parse("https://gitlab.com/a/b/c/-/jobs/3406334")?.target == .job(3406334))
        #expect(parse("https://gitlab.com/a/b/c/-/jobs/3406334")?.projectPath == "a/b/c")
        #expect(parse("https://gitlab.com/a/b/-/merge_requests/12/diffs#note_1")?.target == .mergeRequest(12))
        #expect(parse("https://gitlab.com/a/b/-/commit/8b3c5f0e2a1d")?.target == .commit("8b3c5f0e2a1d"))
        #expect(parse("https://gitlab.com/a/b/-/pipelines/7/failures")?.target == .pipeline(7))
    }

    @Test("A project page or an unknown page points at the project")
    func project() {
        #expect(parse("https://gitlab.com/a/b")?.target == .project)
        #expect(parse("https://gitlab.com/a/b.git")?.projectPath == "a/b")
        #expect(parse("https://gitlab.com/a/b/-/tree/main")?.target == .project)
        #expect(parse("https://gitlab.com/a") == nil)
    }

    @Test("Old links without /-/, ports and instances under a path prefix")
    func variants() {
        #expect(parse("https://gitlab.com/a/b/pipelines/9")?.target == .pipeline(9))
        #expect(parse("https://git.local:8443/a/b/-/jobs/1")?.host == "git.local:8443")
        let prefixed = parse("https://example.com/gitlab/team/app/-/jobs/5", basePath: "/gitlab")
        #expect(prefixed?.projectPath == "team/app")
        #expect(prefixed?.target == .job(5))
    }

    @Test("The token page is on the resource's own instance, with the scope filled in")
    func tokenPage() {
        let page = URL(string: "https://example.com/gitlab").flatMap(GitLabGuide.tokenPage(for:))
        #expect(page?.absoluteString
            == "https://example.com/gitlab/-/user_settings/personal_access_tokens?name=Toolbelt&scopes=read_api")

        let guide = GitLabGuide.guide(for: URL(string: "https://git.local:8443"))
        #expect(guide.steps.first?.link?.url.host() == "git.local")
        #expect(guide.steps.first?.link?.title == "Open Access Tokens on git.local:8443")
    }
}
