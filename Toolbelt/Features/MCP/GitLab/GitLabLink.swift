//
//  GitLabLink.swift
//  Toolbelt
//
//  Reading a pipeline, job, merge request or commit out of a GitLab web link.
//

import Foundation

nonisolated struct GitLabLink: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case pipeline(Int)
        case job(Int)
        case mergeRequest(Int)
        case commit(String)
        case project
    }

    let host: String
    let projectPath: String
    let target: Target
}

nonisolated enum GitLabLinkParser {
    static func host(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// `basePath` is the path of an instance served under a prefix, e.g. https://example.com/gitlab.
    static func parse(_ url: URL, basePath: String = "") -> GitLabLink? {
        guard let host = host(of: url) else { return nil }

        var segments = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        let base = basePath.split(separator: "/").map(String.init)
        if !base.isEmpty, segments.starts(with: base) {
            segments.removeFirst(base.count)
        }

        if let dash = segments.firstIndex(of: "-") {
            guard dash >= 2 else { return nil }
            let rest = Array(segments[(dash + 1)...])
            return GitLabLink(
                host: host,
                projectPath: segments[..<dash].joined(separator: "/"),
                target: target(in: rest) ?? .project
            )
        }

        // Links from older GitLab versions have no "/-/" before the resource.
        if segments.count >= 4 {
            for index in 2..<(segments.count - 1) {
                if let target = target(in: Array(segments[index...])) {
                    return GitLabLink(host: host, projectPath: segments[..<index].joined(separator: "/"), target: target)
                }
            }
        }

        guard segments.count >= 2 else { return nil }
        var path = segments.joined(separator: "/")
        if path.hasSuffix(".git") { path.removeLast(4) }
        return GitLabLink(host: host, projectPath: path, target: .project)
    }

    private static func target(in rest: [String]) -> GitLabLink.Target? {
        guard rest.count >= 2 else { return nil }
        let value = rest[1]
        switch rest[0] {
        case "pipelines":
            return Int(value).map(GitLabLink.Target.pipeline)
        case "jobs", "builds":
            return Int(value).map(GitLabLink.Target.job)
        case "merge_requests":
            return Int(value).map(GitLabLink.Target.mergeRequest)
        case "commit":
            return isCommitSHA(value) ? .commit(value) : nil
        default:
            return nil
        }
    }

    private static func isCommitSHA(_ value: String) -> Bool {
        (7...64).contains(value.count) && value.allSatisfy(\.isHexDigit)
    }
}
