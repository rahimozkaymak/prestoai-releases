import Foundation

struct UserContext: Codable, Equatable {
    enum LearningStyle: String, Codable, CaseIterable {
        case concise
        case stepByStep = "step_by_step"
        case visual
        case socratic

        var description: String {
            switch self {
            case .concise:    return "Concise — short, direct answers"
            case .stepByStep: return "Step-by-step — show every intermediate step"
            case .visual:     return "Visual — use diagrams and visual metaphors"
            case .socratic:   return "Socratic — guide with questions, don't just give answers"
            }
        }
    }

    enum ResponseFormat: String, Codable, CaseIterable {
        case detailed
        case brief
        case examPrep = "exam_prep"

        var description: String {
            switch self {
            case .detailed: return "Detailed — thorough explanations with examples"
            case .brief:    return "Brief — just the essentials"
            case .examPrep: return "Exam prep — focus on likely test questions and key takeaways"
            }
        }
    }

    var name: String?
    var gradeLevel: String?
    var major: String?
    var institution: String?
    var subjects: [String]?
    var learningStyle: LearningStyle?
    var preferredLanguage: String?
    var responseFormat: ResponseFormat?
    var customNotes: [String]?

    var isEmpty: Bool {
        name.isNilOrEmpty
            && gradeLevel.isNilOrEmpty
            && major.isNilOrEmpty
            && institution.isNilOrEmpty
            && (subjects ?? []).isEmpty
            && learningStyle == nil
            && preferredLanguage.isNilOrEmpty
            && responseFormat == nil
            && (customNotes ?? []).isEmpty
    }
}

final class UserContextManager {
    static let shared = UserContextManager()

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("ai.presto.PrestoAI", isDirectory: true)
            .appendingPathComponent("user_context.json")
    }()

    private init() {}

    func load() -> UserContext {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return UserContext()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(UserContext.self, from: data)
        } catch {
            return UserContext()
        }
    }

    func save(_ context: UserContext) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(context)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[UserContextManager] Failed to save: \(error)")
        }
    }

    func renderPromptBlock() -> String {
        let ctx = load()
        guard !ctx.isEmpty else { return "" }

        var lines: [String] = []
        lines.append("<prestoUserContext>")

        func emit(_ tag: String, _ value: String?) {
            guard let v = value, !v.isEmpty else { return }
            lines.append("  <\(tag)>\(v)</\(tag)>")
        }

        emit("name", ctx.name)
        emit("gradeLevel", ctx.gradeLevel)
        emit("major", ctx.major)
        emit("institution", ctx.institution)

        if let subjects = ctx.subjects, !subjects.isEmpty {
            emit("subjects", subjects.joined(separator: ", "))
        }

        emit("learningStyle", ctx.learningStyle?.rawValue)
        emit("preferredLanguage", ctx.preferredLanguage)
        emit("responseFormat", ctx.responseFormat?.rawValue)

        if let notes = ctx.customNotes, !notes.isEmpty {
            lines.append("  <customNotes>")
            for note in notes {
                lines.append("    <note>\(note)</note>")
            }
            lines.append("  </customNotes>")
        }

        lines.append("</prestoUserContext>")
        return lines.joined(separator: "\n")
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}
