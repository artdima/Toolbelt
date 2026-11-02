//
//  GitLabModels.swift
//  Toolbelt
//
//  GitLab REST v4 responses, decoded with convertFromSnakeCase.
//

import Foundation

nonisolated struct GitLabUser: Decodable, Sendable {
    let id: Int
    let username: String
    let name: String?
}

nonisolated struct GitLabUserRef: Decodable, Sendable {
    let username: String?
    let name: String?

    var label: String { username.map { "@\($0)" } ?? name ?? "unknown" }
}

nonisolated struct GitLabTokenInfo: Decodable, Sendable {
    let name: String?
    let scopes: [String]?
    let expiresAt: String?
    let active: Bool?
    let revoked: Bool?
}

nonisolated struct GitLabPipelineRef: Decodable, Sendable {
    let id: Int
    let status: String?
    let ref: String?
    let sha: String?
    let webUrl: String?
    let projectId: Int?
}

nonisolated struct GitLabPipeline: Decodable, Sendable {
    let id: Int
    let iid: Int?
    let projectId: Int?
    let status: String
    let ref: String?
    let sha: String?
    let source: String?
    let tag: Bool?
    let createdAt: String?
    let updatedAt: String?
    let startedAt: String?
    let finishedAt: String?
    let duration: Double?
    let queuedDuration: Double?
    let webUrl: String?
    let user: GitLabUserRef?
}

nonisolated struct GitLabCommit: Decodable, Sendable {
    let id: String
    let shortId: String?
    let title: String?
    let message: String?
    let authorName: String?
    let authoredDate: String?
    let webUrl: String?
    let lastPipeline: GitLabPipelineRef?
}

nonisolated struct GitLabRunner: Decodable, Sendable {
    let id: Int?
    let description: String?
    let name: String?
}

nonisolated struct GitLabJob: Decodable, Sendable {
    let id: Int
    let name: String
    let stage: String?
    let status: String
    let duration: Double?
    let queuedDuration: Double?
    let failureReason: String?
    let allowFailure: Bool?
    let webUrl: String?
    let startedAt: String?
    let finishedAt: String?
    let runner: GitLabRunner?
    let pipeline: GitLabPipelineRef?
    let ref: String?
}

nonisolated struct GitLabBridge: Decodable, Sendable {
    let id: Int
    let name: String
    let stage: String?
    let status: String
    let duration: Double?
    let failureReason: String?
    let allowFailure: Bool?
    let webUrl: String?
    let downstreamPipeline: GitLabPipelineRef?
}

nonisolated struct GitLabMergeRequest: Decodable, Sendable {
    let id: Int
    let iid: Int
    let title: String
    let description: String?
    let state: String
    let draft: Bool?
    let author: GitLabUserRef?
    let assignees: [GitLabUserRef]?
    let reviewers: [GitLabUserRef]?
    let sourceBranch: String?
    let targetBranch: String?
    let hasConflicts: Bool?
    let detailedMergeStatus: String?
    let mergeStatus: String?
    let webUrl: String?
    let createdAt: String?
    let updatedAt: String?
    let mergedAt: String?
    let sha: String?
    let labels: [String]?
    let changesCount: String?
    let headPipeline: GitLabPipelineRef?
    let diffRefs: GitLabDiffRefs?
    let userNotesCount: Int?
}

nonisolated struct GitLabDiffRefs: Decodable, Sendable {
    let baseSha: String?
    let startSha: String?
    let headSha: String?
}

nonisolated struct GitLabDiff: Decodable, Sendable {
    let oldPath: String
    let newPath: String
    let newFile: Bool?
    let renamedFile: Bool?
    let deletedFile: Bool?
    let diff: String?
    let tooLarge: Bool?
    let collapsed: Bool?

    /// The diff body has no ---/+++ header, so every +/- line is a changed line.
    var lineCounts: (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in (diff ?? "").split(separator: "\n") {
            if line.hasPrefix("+") {
                added += 1
            } else if line.hasPrefix("-") {
                removed += 1
            }
        }
        return (added, removed)
    }
}

nonisolated struct GitLabChanges: Decodable, Sendable {
    let changes: [GitLabDiff]
}

nonisolated struct GitLabDiscussion: Decodable, Sendable {
    let id: String
    let individualNote: Bool?
    let notes: [GitLabNote]

    var isSystem: Bool { notes.allSatisfy { $0.system == true } }
    var isResolvable: Bool { notes.contains { $0.resolvable == true } }
    /// GitLab keeps the resolved flag on every resolvable note of a thread, not on the thread.
    var isResolved: Bool {
        let resolvable = notes.filter { $0.resolvable == true }
        return !resolvable.isEmpty && resolvable.allSatisfy { $0.resolved == true }
    }
    var isUnresolved: Bool { isResolvable && !isResolved }
    var resolvedBy: GitLabUserRef? { notes.first { $0.resolvedBy != nil }?.resolvedBy }
    var position: GitLabNotePosition? { notes.first { $0.position != nil }?.position }
}

nonisolated struct GitLabNote: Decodable, Sendable {
    let id: Int
    let body: String?
    let author: GitLabUserRef?
    let createdAt: String?
    let system: Bool?
    let resolvable: Bool?
    let resolved: Bool?
    let resolvedBy: GitLabUserRef?
    let position: GitLabNotePosition?
}

nonisolated struct GitLabNotePosition: Decodable, Sendable {
    let positionType: String?
    let headSha: String?
    let oldPath: String?
    let newPath: String?
    let oldLine: Int?
    let newLine: Int?
    let lineRange: GitLabLineRange?

    var paths: [String] { [newPath, oldPath].compactMap { $0 } }
}

nonisolated struct GitLabLineRange: Decodable, Sendable {
    let start: GitLabLinePoint?
    let end: GitLabLinePoint?
}

nonisolated struct GitLabLinePoint: Decodable, Sendable {
    let oldLine: Int?
    let newLine: Int?

    var line: Int? { newLine ?? oldLine }
}

nonisolated enum GitLabThreadStatus: String, CaseIterable, Sendable {
    case all
    case unresolved
    case resolved

    func includes(_ discussion: GitLabDiscussion) -> Bool {
        switch self {
        case .all: true
        case .unresolved: discussion.isUnresolved
        case .resolved: discussion.isResolved
        }
    }
}

nonisolated struct GitLabErrorBody: Decodable, Sendable {
    let message: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        if let text = try? container.decodeIfPresent(String.self, forKey: .message) {
            message = text
        } else if let fields = try? container.decodeIfPresent([String: [String]].self, forKey: .message) {
            message = fields.sorted { $0.key < $1.key }
                .map { "\($0.key) \($0.value.joined(separator: ", "))" }
                .joined(separator: "; ")
        } else {
            message = nil
        }
    }
}
