import Foundation

// MARK: - Question State

enum QuestionState: String {
    case pending
    case solving
    case solved
    case failed
    case skipped
}

enum QuestionType: String, Codable {
    case freeResponse = "free_response"
    case multipleChoice = "multiple_choice"
    case trueFalse = "true_false"
    case fillInBlank = "fill_in_blank"
}

enum DocumentType: String, Codable {
    case exam
    case problemSet = "problem_set"
    case textbook
    case worksheet
    case unknown
}

enum Difficulty: String, Codable {
    case easy, medium, hard
}

// MARK: - Solved Answer

struct SolvedAnswer {
    let latex: String
    let copyable: String
    let isMultipleChoice: Bool
    let multipleChoiceLetter: String?
    let confidence: Double
    let solvedAt: Date
}

// MARK: - Solution Step

struct SolutionStep {
    let stepNumber: Int
    let latex: String
    let explanation: String
    let isKeyStep: Bool
}

// MARK: - Concept Explanation

struct ConceptExplanation {
    let conceptName: String
    let conceptExplanation: String
    let formulaLatex: String?
    let strategy: String?
    let similarExample: SimilarExample?
    let commonMistakes: [String]
}

struct SimilarExample {
    let problemLatex: String
    let solutionLatex: String
    let steps: [SolutionStep]
}

// MARK: - Work Check Feedback

struct WorkCheckFeedback {
    let isCorrect: Bool
    let correctnessPercentage: Int
    let feedback: String
    let errorStep: Int?
    let errorType: String?
    let correctFromError: String?
    let encouragement: String?
}

// MARK: - User Attempt

struct UserAttempt {
    let attemptText: String?
    let attemptImage: String?  // base64
    let feedback: WorkCheckFeedback?
    let attemptedAt: Date
}

// MARK: - Question Record

class QuestionRecord {
    let id: String
    let questionText: String
    let answerBoxHint: String?
    let detectedPage: Int
    let detectedAt: Date
    let questionType: QuestionType
    let positionOnPage: Int

    var topic: String?
    var difficulty: Difficulty?

    // Solve results
    var answer: SolvedAnswer?
    var steps: [SolutionStep]?
    var explanation: ConceptExplanation?
    var userAttempt: UserAttempt?
    var state: QuestionState = .pending

    // Steps loading
    var stepsLoading: Bool = false

    init(id: String, questionText: String, answerBoxHint: String? = nil,
         detectedPage: Int, questionType: QuestionType = .freeResponse,
         positionOnPage: Int = 0, topic: String? = nil, difficulty: Difficulty? = nil) {
        self.id = id
        self.questionText = questionText
        self.answerBoxHint = answerBoxHint
        self.detectedPage = detectedPage
        self.detectedAt = Date()
        self.questionType = questionType
        self.positionOnPage = positionOnPage
        self.topic = topic
        self.difficulty = difficulty
    }
}

// MARK: - Study Mode

enum StudyMode {
    case solve
    case learn
}

// MARK: - Session Memory

class SessionMemory {
    // Document understanding
    var globalContext: String = ""
    var documentType: DocumentType = .unknown

    // Question registry — single source of truth
    var questions: [String: QuestionRecord] = [:]
    var questionOrder: [String] = []
    var pageMap: [Int: [String]] = [:]

    // Page tracking
    var currentPage: Int = 1
    var totalPagesDetected: Int = 1
    var pageContentHashes: [Int: UInt64] = [:]

    // Content fingerprints
    var lastContentHash: UInt64 = 0

    // Learn state
    var conceptsCovered: [String] = []

    // Session timing
    var modeTimeSolveSeconds: Int = 0
    var modeTimeLearnSeconds: Int = 0
    var lastModeSwitch: Date = Date()

    // MARK: - Computed

    var solvedQuestions: Set<String> {
        Set(questions.values.filter { $0.state == .solved }.map { $0.id })
    }

    var failedQuestions: Set<String> {
        Set(questions.values.filter { $0.state == .failed }.map { $0.id })
    }

    var pendingQuestions: [QuestionRecord] {
        questionOrder.compactMap { questions[$0] }.filter { $0.state == .pending }
    }

    var unsolvedQuestions: [QuestionRecord] {
        questionOrder.compactMap { questions[$0] }.filter { $0.state == .pending || $0.state == .failed }
    }

    var allQuestionsOrdered: [QuestionRecord] {
        questionOrder.compactMap { questions[$0] }
    }

    var solversInFlightCount: Int {
        questions.values.filter { $0.state == .solving }.count
    }

    var totalCount: Int { questions.count }
    var solvedCount: Int { solvedQuestions.count }

    // MARK: - Question Text Fragments (for scroll vs page detection)

    func allQuestionTextFragments() -> Set<String> {
        var fragments = Set<String>()
        for q in questions.values {
            let words = q.questionText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count >= 3 }
                .map { $0.lowercased() }
            fragments.formUnion(words)
        }
        return fragments
    }

    // MARK: - Mutations

    func addQuestion(_ record: QuestionRecord) {
        guard questions[record.id] == nil else { return } // dedup
        questions[record.id] = record
        questionOrder.append(record.id)
        pageMap[record.detectedPage, default: []].append(record.id)
    }

    func markSolving(_ id: String) {
        questions[id]?.state = .solving
    }

    func markSolved(_ id: String, answer: SolvedAnswer) {
        guard let q = questions[id] else { return }
        q.state = .solved
        q.answer = answer
        if let topic = q.topic, !conceptsCovered.contains(topic) {
            conceptsCovered.append(topic)
        }
    }

    func markFailed(_ id: String) {
        questions[id]?.state = .failed
    }

    func setSteps(_ id: String, steps: [SolutionStep]) {
        questions[id]?.steps = steps
        questions[id]?.stepsLoading = false
    }

    func resetForRetry(_ id: String) {
        let q = questions[id]
        q?.state = .pending
        q?.answer = nil
        q?.steps = nil
    }

    // MARK: - Context Building

    func buildSolveContext(for questionId: String) -> SolveContext? {
        guard let question = questions[questionId] else { return nil }

        // Neighboring questions for notation context
        let pageQuestions = pageMap[question.detectedPage] ?? []
        let neighbors = pageQuestions
            .filter { $0 != questionId }
            .prefix(2)
            .compactMap { questions[$0]?.questionText }

        return SolveContext(
            globalContext: globalContext,
            documentType: documentType,
            questionText: question.questionText,
            answerBoxHint: question.answerBoxHint,
            questionType: question.questionType,
            neighboringQuestions: Array(neighbors),
            previouslySolvedTopics: conceptsCovered
        )
    }

    // MARK: - Mode Time Tracking

    func recordModeTime(mode: StudyMode) {
        let elapsed = Int(Date().timeIntervalSince(lastModeSwitch))
        switch mode {
        case .solve: modeTimeSolveSeconds += elapsed
        case .learn: modeTimeLearnSeconds += elapsed
        }
        lastModeSwitch = Date()
    }
}

// MARK: - Solve Context (passed to API)

struct SolveContext {
    let globalContext: String
    let documentType: DocumentType
    let questionText: String
    let answerBoxHint: String?
    let questionType: QuestionType
    let neighboringQuestions: [String]
    let previouslySolvedTopics: [String]
}
