import Foundation

// MARK: - Solve Result

enum SolveResult {
    case solved(answer: SolvedAnswer, topic: String?, steps: [SolutionStep]?)
    case failed(error: Error)
}

// MARK: - Solver Engine

@MainActor
class SolverEngine {
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private(set) var solversInFlight: Int = 0

    var sessionId: String = ""

    // MARK: - Batch Solve

    func batchSolve(
        questions: [QuestionRecord],
        memory: SessionMemory,
        onEachResult: @escaping (String, SolveResult) -> Void
    ) {
        for question in questions where question.state == .pending || question.state == .failed {
            question.state = .solving
            solversInFlight += 1

            let questionId = question.id
            let context = memory.buildSolveContext(for: questionId)

            let task = Task { [weak self] in
                guard let context = context else {
                    await MainActor.run {
                        self?.solversInFlight = max(0, (self?.solversInFlight ?? 1) - 1)
                        onEachResult(questionId, .failed(error: APIError.serverError("No context")))
                    }
                    return
                }

                do {
                    let result = try await APIService.shared.studySolve(
                        sessionId: self?.sessionId ?? "",
                        questionId: questionId,
                        questionText: context.questionText,
                        globalContext: context.globalContext,
                        answerBoxHint: context.answerBoxHint,
                        questionType: context.questionType,
                        neighboringQuestions: context.neighboringQuestions,
                        includeSteps: false
                    )

                    let answer = SolvedAnswer(
                        latex: result.answerLatex,
                        copyable: result.answerCopyable,
                        isMultipleChoice: result.isMultipleChoice,
                        multipleChoiceLetter: result.multipleChoiceLetter,
                        confidence: result.confidence,
                        solvedAt: Date()
                    )

                    await MainActor.run {
                        self?.solversInFlight = max(0, (self?.solversInFlight ?? 1) - 1)
                        self?.activeTasks.removeValue(forKey: questionId)
                        onEachResult(questionId, .solved(answer: answer, topic: result.topic, steps: nil))
                    }
                } catch {
                    await MainActor.run {
                        self?.solversInFlight = max(0, (self?.solversInFlight ?? 1) - 1)
                        self?.activeTasks.removeValue(forKey: questionId)
                        onEachResult(questionId, .failed(error: error))
                    }
                }
            }

            activeTasks[questionId] = task
        }
    }

    // MARK: - Single Solve (with retry)

    func solveSingle(
        questionId: String,
        memory: SessionMemory,
        onResult: @escaping (String, SolveResult) -> Void
    ) {
        guard let question = memory.questions[questionId] else { return }
        question.state = .solving
        solversInFlight += 1

        let context = memory.buildSolveContext(for: questionId)

        let task = Task { [weak self] in
            guard let context = context else {
                await MainActor.run {
                    self?.solversInFlight = max(0, (self?.solversInFlight ?? 1) - 1)
                    onResult(questionId, .failed(error: APIError.serverError("No context")))
                }
                return
            }

            do {
                let result = try await APIService.shared.studySolve(
                    sessionId: self?.sessionId ?? "",
                    questionId: questionId,
                    questionText: context.questionText,
                    globalContext: context.globalContext,
                    answerBoxHint: context.answerBoxHint,
                    questionType: context.questionType,
                    neighboringQuestions: context.neighboringQuestions,
                    includeSteps: false
                )

                let answer = SolvedAnswer(
                    latex: result.answerLatex,
                    copyable: result.answerCopyable,
                    isMultipleChoice: result.isMultipleChoice,
                    multipleChoiceLetter: result.multipleChoiceLetter,
                    confidence: result.confidence,
                    solvedAt: Date()
                )

                await MainActor.run {
                    self?.solversInFlight = max(0, (self?.solversInFlight ?? 1) - 1)
                    self?.activeTasks.removeValue(forKey: questionId)
                    onResult(questionId, .solved(answer: answer, topic: result.topic, steps: nil))
                }
            } catch {
                await MainActor.run {
                    self?.solversInFlight = max(0, (self?.solversInFlight ?? 1) - 1)
                    self?.activeTasks.removeValue(forKey: questionId)
                    onResult(questionId, .failed(error: error))
                }
            }
        }

        activeTasks[questionId] = task
    }

    // MARK: - Lazy Step Loading

    func loadSteps(
        questionId: String,
        memory: SessionMemory,
        onResult: @escaping (String, [SolutionStep]?) -> Void
    ) {
        guard let question = memory.questions[questionId],
              question.state == .solved,
              question.steps == nil else { return }

        question.stepsLoading = true
        let context = memory.buildSolveContext(for: questionId)

        Task { [weak self] in
            guard let context = context else {
                await MainActor.run {
                    memory.questions[questionId]?.stepsLoading = false
                    onResult(questionId, nil)
                }
                return
            }

            do {
                let result = try await APIService.shared.studySolve(
                    sessionId: self?.sessionId ?? "",
                    questionId: questionId,
                    questionText: context.questionText,
                    globalContext: context.globalContext,
                    answerBoxHint: context.answerBoxHint,
                    questionType: context.questionType,
                    neighboringQuestions: context.neighboringQuestions,
                    includeSteps: true
                )

                let steps = result.steps?.map { s in
                    SolutionStep(
                        stepNumber: s.stepNumber,
                        latex: s.latex,
                        explanation: s.explanation,
                        isKeyStep: s.isKeyStep
                    )
                }

                await MainActor.run {
                    if let steps = steps {
                        memory.setSteps(questionId, steps: steps)
                    } else {
                        memory.questions[questionId]?.stepsLoading = false
                    }
                    onResult(questionId, steps)
                }
            } catch {
                await MainActor.run {
                    memory.questions[questionId]?.stepsLoading = false
                    onResult(questionId, nil)
                }
            }
        }
    }

    // MARK: - Cancel

    func cancelAll() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
        solversInFlight = 0
    }

    func cancelQuestion(_ questionId: String) {
        activeTasks[questionId]?.cancel()
        activeTasks.removeValue(forKey: questionId)
        solversInFlight = max(0, solversInFlight - 1)
    }
}
