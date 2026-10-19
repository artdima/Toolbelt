//
//  GitLabFormatter.swift
//  Toolbelt
//
//  GitLab objects as compact text for the model: the fields that matter and web links,
//  never raw JSON.
//

import Foundation

nonisolated struct GitLabFormatter: Sendable {
    let timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    // MARK: Pipelines

    func pipelines(_ pipelines: [GitLabPipeline], project: String, filters: [String]) -> String {
        let scope = filters.isEmpty ? "" : " (\(filters.joined(separator: ", ")))"
        guard !pipelines.isEmpty else { return "No pipelines in \(project)\(scope)." }

        var lines = ["Latest \(pipelines.count) pipelines in \(project)\(scope), newest first:"]
        for pipeline in pipelines {
            lines.append(pipelineLine(pipeline))
            if let url = pipeline.webUrl { lines.append("  \(url)") }
        }
        return lines.joined(separator: "\n")
    }

    func pipelineLine(_ pipeline: GitLabPipeline) -> String {
        var parts = ["\(Self.mark(pipeline.status)) #\(pipeline.id) \(pipeline.status)"]
        if let ref = pipeline.ref { parts.append("ref \(ref)") }
        if let sha = pipeline.sha { parts.append(String(sha.prefix(8))) }
        if let user = pipeline.user { parts.append(user.label) }
        if let created = time(pipeline.createdAt) { parts.append(created) }
        if let duration = Self.duration(pipeline.duration) { parts.append(duration) }
        return parts.joined(separator: " · ")
    }

    func pipeline(
        _ pipeline: GitLabPipeline,
        project: String,
        commit: GitLabCommit?,
        jobs: [GitLabJob],
        bridges: [GitLabBridge],
        isComplete: Bool
    ) -> String {
        var lines = ["Pipeline #\(pipeline.id) · \(pipeline.status) · \(project)"]

        var refLine: [String] = []
        if let ref = pipeline.ref { refLine.append("ref \(ref)\(pipeline.tag == true ? " (tag)" : "")") }
        if let sha = pipeline.sha { refLine.append("sha \(sha)") }
        if !refLine.isEmpty { lines.append(refLine.joined(separator: " · ")) }

        if let commit {
            let title = commit.title ?? Self.firstLine(commit.message) ?? commit.id
            let author = commit.authorName.map { " — \($0)" } ?? ""
            lines.append("Commit: \(title)\(author)")
        }

        var timing: [String] = []
        if let user = pipeline.user { timing.append("by \(user.label)") }
        if let source = pipeline.source { timing.append("source \(source)") }
        if let created = time(pipeline.createdAt) { timing.append("created \(created)") }
        if let finished = time(pipeline.finishedAt) { timing.append("finished \(finished)") }
        if let duration = Self.duration(pipeline.duration) { timing.append("duration \(duration)") }
        if !timing.isEmpty { lines.append(timing.joined(separator: " · ")) }
        if let url = pipeline.webUrl { lines.append(url) }

        let entries = (jobs.map(PipelineEntry.job) + bridges.map(PipelineEntry.bridge))
            .sorted(by: PipelineEntry.failedFirst)
        let failed = entries.filter(\.isFailed).count

        lines.append("")
        if entries.isEmpty {
            lines.append("No jobs or triggers.")
        } else {
            var summary = "Jobs and triggers — \(entries.count)"
            if failed > 0 { summary += ", \(failed) failed (listed first)" }
            lines.append(summary + ":")
            lines += entries.map(entryLine)
            if !isComplete {
                lines.append("[Only the first pages of jobs were loaded; the pipeline has more.]")
            }
            if let projectURL = pipeline.webUrl.flatMap(Self.projectURL) {
                lines.append("Job pages: \(projectURL)/-/jobs/<id>")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func entryLine(_ entry: PipelineEntry) -> String {
        switch entry {
        case let .job(job):
            var parts = ["\(Self.mark(job.status)) \(job.status)", "job \(job.name) #\(job.id)"]
            if let stage = job.stage { parts.append("stage \(stage)") }
            if let duration = Self.duration(job.duration) { parts.append(duration) }
            if let reason = job.failureReason { parts.append("failure_reason \(reason)") }
            if job.allowFailure == true { parts.append("allowed to fail") }
            if job.status == "failed", let url = job.webUrl { parts.append(url) }
            return parts.joined(separator: " · ")
        case let .bridge(bridge):
            var parts = ["\(Self.mark(bridge.status)) \(bridge.status)", "trigger \(bridge.name) #\(bridge.id)"]
            if let stage = bridge.stage { parts.append("stage \(stage)") }
            if let reason = bridge.failureReason { parts.append("failure_reason \(reason)") }
            if bridge.allowFailure == true { parts.append("allowed to fail") }
            if let downstream = bridge.downstreamPipeline {
                var child = "downstream pipeline #\(downstream.id)"
                if let status = downstream.status { child += " \(status)" }
                if let project = downstream.webUrl.flatMap(Self.projectPath(fromWebURL:)) { child += " in \(project)" }
                if let url = downstream.webUrl { child += " \(url)" }
                parts.append(child)
            } else {
                parts.append("downstream pipeline: not created")
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: Jobs

    func jobHeader(_ job: GitLabJob) -> String {
        var lines = ["Job #\(job.id) · \(job.name) · \(job.status)"]

        var context: [String] = []
        if let stage = job.stage { context.append("stage \(stage)") }
        if let pipeline = job.pipeline { context.append("pipeline #\(pipeline.id)") }
        if let ref = job.ref ?? job.pipeline?.ref { context.append("ref \(ref)") }
        if !context.isEmpty { lines.append(context.joined(separator: " · ")) }

        var run: [String] = []
        if let runner = job.runner {
            let name = runner.description ?? runner.name ?? "unnamed"
            run.append("runner \(name)\(runner.id.map { " (#\($0))" } ?? "")")
        }
        if let duration = Self.duration(job.duration) { run.append("duration \(duration)") }
        if let queued = Self.duration(job.queuedDuration) { run.append("queued \(queued)") }
        if let finished = time(job.finishedAt) { run.append("finished \(finished)") }
        if !run.isEmpty { lines.append(run.joined(separator: " · ")) }

        lines.append("failure_reason: \(job.failureReason ?? "—")\(job.allowFailure == true ? " (allowed to fail)" : "")")
        if let url = job.webUrl { lines.append(url) }
        return lines.joined(separator: "\n")
    }

    // MARK: Merge requests

    func mergeRequests(_ requests: [GitLabMergeRequest], project: String, filters: [String]) -> String {
        let scope = filters.isEmpty ? "" : " (\(filters.joined(separator: ", ")))"
        guard !requests.isEmpty else { return "No merge requests in \(project)\(scope)." }

        var lines = ["\(requests.count) merge requests in \(project)\(scope), recently updated first:"]
        for request in requests {
            var parts = ["!\(request.iid) \(request.title)", request.state]
            if request.draft == true { parts.append("draft") }
            if let author = request.author { parts.append(author.label) }
            if let branches = Self.branches(request) { parts.append(branches) }
            if let updated = time(request.updatedAt) { parts.append("updated \(updated)") }
            if request.hasConflicts == true { parts.append("has conflicts") }
            if let pipeline = request.headPipeline, let status = pipeline.status { parts.append("pipeline \(status)") }
            lines.append(parts.joined(separator: " · "))
            if let url = request.webUrl { lines.append("  \(url)") }
        }
        return lines.joined(separator: "\n")
    }

    func mergeRequest(_ request: GitLabMergeRequest, diffs: [GitLabDiff], isComplete: Bool) -> String {
        var lines = ["!\(request.iid) \(request.title)"]

        var state = ["state \(request.state)\(request.draft == true ? " (draft)" : "")"]
        if let status = request.detailedMergeStatus ?? request.mergeStatus { state.append("merge status \(status)") }
        state.append(request.hasConflicts == true ? "has conflicts" : "no conflicts")
        lines.append(state.joined(separator: " · "))

        var people: [String] = []
        if let author = request.author { people.append("author \(author.label)") }
        if let assignees = request.assignees, !assignees.isEmpty {
            people.append("assignees " + assignees.map(\.label).joined(separator: ", "))
        }
        if let reviewers = request.reviewers, !reviewers.isEmpty {
            people.append("reviewers " + reviewers.map(\.label).joined(separator: ", "))
        }
        if !people.isEmpty { lines.append(people.joined(separator: " · ")) }

        if let branches = Self.branches(request) { lines.append("Branches: \(branches)") }

        var dates: [String] = []
        if let created = time(request.createdAt) { dates.append("created \(created)") }
        if let updated = time(request.updatedAt) { dates.append("updated \(updated)") }
        if let merged = time(request.mergedAt) { dates.append("merged \(merged)") }
        if !dates.isEmpty { lines.append(dates.joined(separator: " · ")) }

        if let labels = request.labels, !labels.isEmpty { lines.append("Labels: \(labels.joined(separator: ", "))") }

        if let pipeline = request.headPipeline {
            var text = "Latest pipeline: #\(pipeline.id)"
            if let status = pipeline.status { text += " \(status)" }
            if let url = pipeline.webUrl { text += " · \(url)" }
            lines.append(text)
        } else {
            lines.append("Latest pipeline: none")
        }
        if let url = request.webUrl { lines.append(url) }

        let description = request.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        lines.append("")
        lines.append("Description:")
        lines.append(description.isEmpty ? "(empty)" : MCPText.truncated(description, to: 4_000))

        let totals = diffs.reduce(into: (added: 0, removed: 0)) { sum, diff in
            let counts = diff.lineCounts
            sum.added += counts.added
            sum.removed += counts.removed
        }
        lines.append("")
        lines.append("Changed files — \(diffs.count) (+\(totals.added) −\(totals.removed)):")
        for diff in diffs {
            let counts = diff.lineCounts
            var line = "\(Self.changeMark(diff)) \(Self.path(of: diff))  +\(counts.added) −\(counts.removed)"
            if diff.tooLarge == true || diff.collapsed == true { line += " (diff not shown by GitLab: too large)" }
            lines.append(line)
        }
        if !isComplete { lines.append("[Only the first pages of changed files were loaded.]") }
        if !diffs.isEmpty { lines.append("Call gitlab_merge_request with file: \"<path>\" to see one file's diff.") }
        return lines.joined(separator: "\n")
    }

    func fileDiff(_ diff: GitLabDiff, request: GitLabMergeRequest) -> (header: String, body: String) {
        let counts = diff.lineCounts
        let header = "!\(request.iid) \(request.title)\n\(Self.changeMark(diff)) \(Self.path(of: diff))  +\(counts.added) −\(counts.removed)"
        guard let text = diff.diff, !text.isEmpty else {
            return (header, "GitLab returned no diff for this file\(diff.tooLarge == true ? ": it is too large" : "").")
        }
        return (header, text)
    }

    // MARK: Commits

    func commit(_ commit: GitLabCommit, project: String, pipelines: [GitLabPipeline]) -> String {
        var lines = ["Commit \(commit.shortId ?? String(commit.id.prefix(8))) in \(project) · \(commit.title ?? "")"]
        lines.append("sha \(commit.id)")
        var meta: [String] = []
        if let author = commit.authorName { meta.append("author \(author)") }
        if let date = time(commit.authoredDate) { meta.append("authored \(date)") }
        if !meta.isEmpty { lines.append(meta.joined(separator: " · ")) }
        if let url = commit.webUrl { lines.append(url) }

        if let message = commit.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            lines.append("")
            lines.append("Message:")
            lines.append(MCPText.truncated(message, to: 4_000))
        }

        lines.append("")
        if pipelines.isEmpty {
            lines.append("No pipelines for this commit.")
        } else {
            lines.append("Pipelines for this commit — \(pipelines.count):")
            for pipeline in pipelines {
                lines.append(pipelineLine(pipeline))
                if let url = pipeline.webUrl { lines.append("  \(url)") }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Values

    func time(_ value: String?) -> String? {
        guard let value, let date = Self.parseDate(value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let offset = timeZone.secondsFromGMT(for: date) / 60
        let local = String(
            format: "%04ld-%02ld-%02ld %02ld:%02ld",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
        let zone = String(format: "%02ld:%02ld", abs(offset) / 60, abs(offset) % 60)
        return local + (offset < 0 ? "-" : "+") + zone
    }

    static func parseDate(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return rest > 0 ? "\(minutes)m \(rest)s" : "\(minutes)m" }
        return "\(rest)s"
    }

    static func mark(_ status: String) -> String {
        switch status {
        case "success": "✓"
        case "failed": "✗"
        case "canceled", "canceling": "⊘"
        case "skipped": "○"
        case "running": "▶"
        case "manual": "⏸"
        default: "…"
        }
    }

    /// "https://host/group/project/-/pipelines/1" → "group/project".
    static func projectPath(fromWebURL value: String) -> String? {
        guard let url = URL(string: value) else { return nil }
        let segments = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        guard let dash = segments.firstIndex(of: "-"), dash > 0 else { return nil }
        return segments[..<dash].joined(separator: "/")
    }

    private static func projectURL(_ value: String) -> String? {
        guard let range = value.range(of: "/-/") else { return nil }
        return String(value[..<range.lowerBound])
    }

    private static func firstLine(_ text: String?) -> String? {
        text?.split(separator: "\n", maxSplits: 1).first.map(String.init)
    }

    private static func branches(_ request: GitLabMergeRequest) -> String? {
        guard let source = request.sourceBranch, let target = request.targetBranch else { return nil }
        return "\(source) → \(target)"
    }

    private static func path(of diff: GitLabDiff) -> String {
        diff.renamedFile == true && diff.oldPath != diff.newPath ? "\(diff.oldPath) → \(diff.newPath)" : diff.newPath
    }

    private static func changeMark(_ diff: GitLabDiff) -> String {
        if diff.newFile == true { return "A" }
        if diff.deletedFile == true { return "D" }
        if diff.renamedFile == true { return "R" }
        return "M"
    }
}

nonisolated private enum PipelineEntry {
    case job(GitLabJob)
    case bridge(GitLabBridge)

    var id: Int {
        switch self {
        case let .job(job): job.id
        case let .bridge(bridge): bridge.id
        }
    }

    var isFailed: Bool {
        switch self {
        case let .job(job): job.status == "failed"
        case let .bridge(bridge): bridge.status == "failed"
        }
    }

    private var rank: Int {
        switch self {
        case let .job(job) where job.status == "failed": job.allowFailure == true ? 1 : 0
        case let .bridge(bridge) where bridge.status == "failed": bridge.allowFailure == true ? 1 : 0
        default: 2
        }
    }

    static func failedFirst(_ lhs: PipelineEntry, _ rhs: PipelineEntry) -> Bool {
        lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.id < rhs.id
    }
}
