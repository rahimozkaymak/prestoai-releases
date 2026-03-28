import SwiftUI

struct UserContextSettingsView: View {
    typealias LearningStyle = UserContext.LearningStyle
    typealias ResponseFormat = UserContext.ResponseFormat
    @State private var context = UserContextManager.shared.load()
    @State private var newNote = ""
    @State private var newSubject = ""
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Privacy notice
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("This data never leaves your device.")
                        .font(.system(size: 11))
                }
                .foregroundColor(Theme.text4(colorScheme))
                .padding(.top, 4)

                // Name
                fieldSection("Name") {
                    contextTextField("Your name", text: binding(\.name))
                }

                // Grade Level
                fieldSection("Academic Level") {
                    Picker("", selection: gradeBinding) {
                        Text("Not set").tag("")
                        ForEach(gradeLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Institution
                fieldSection("School / Institution") {
                    contextTextField("e.g. University of Miami", text: binding(\.institution))
                }

                // Major
                fieldSection("Major / Field") {
                    contextTextField("e.g. Computer Science", text: binding(\.major))
                }

                // Subjects
                fieldSection("Current Subjects") {
                    VStack(alignment: .leading, spacing: 6) {
                        FlowLayout(spacing: 6) {
                            ForEach((context.subjects ?? []), id: \.self) { subject in
                                HStack(spacing: 4) {
                                    Text(subject)
                                        .font(.system(size: 12))
                                    Button(action: { context.subjects?.removeAll { $0 == subject }; save() }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundColor(Theme.text2(colorScheme))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Theme.subtleBg(colorScheme))
                                .cornerRadius(6)
                            }
                        }

                        HStack(spacing: 6) {
                            TextField("Add subject…", text: $newSubject)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.text1(colorScheme))
                                .onSubmit { addSubject() }

                            Button("Add") { addSubject() }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                                .buttonStyle(.plain)
                                .disabled(newSubject.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(8)
                        .background(Theme.inputBg(colorScheme))
                        .cornerRadius(8)
                    }
                }

                // Learning Style
                fieldSection("Learning Style") {
                    Picker("", selection: learningStyleBinding) {
                        Text("Not set").tag(LearningStyle?.none as LearningStyle?)
                        ForEach(LearningStyle.allCases, id: \.self) { style in
                            Text(style.description).tag(Optional(style))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Response Format
                fieldSection("Response Format") {
                    Picker("", selection: responseFormatBinding) {
                        Text("Not set").tag(ResponseFormat?.none as ResponseFormat?)
                        ForEach(ResponseFormat.allCases, id: \.self) { fmt in
                            Text(fmt.description).tag(Optional(fmt))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Preferred Language
                fieldSection("Preferred Language") {
                    contextTextField("e.g. English, Turkish", text: binding(\.preferredLanguage))
                }

                // Custom Notes
                fieldSection("Custom Notes") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array((context.customNotes ?? []).enumerated()), id: \.offset) { i, note in
                            HStack {
                                Text("• \(note)")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.text2(colorScheme))
                                Spacer()
                                Button(action: { context.customNotes?.remove(at: i); save() }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Theme.text4(colorScheme))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack(spacing: 6) {
                            TextField("e.g. I prefer LaTeX for math", text: $newNote)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.text1(colorScheme))
                                .onSubmit { addNote() }

                            Button("Add") { addNote() }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                                .buttonStyle(.plain)
                                .disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(8)
                        .background(Theme.inputBg(colorScheme))
                        .cornerRadius(8)
                    }
                }

                // Clear All
                Button(action: {
                    context = UserContext()
                    save()
                }) {
                    Text("Clear All")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text4(colorScheme))
            content()
        }
    }

    private func contextTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(Theme.text1(colorScheme))
            .padding(10)
            .background(Theme.inputBg(colorScheme))
            .cornerRadius(8)
            .onChange(of: text.wrappedValue) { _ in save() }
    }

    private func binding(_ keyPath: WritableKeyPath<UserContext, String?>) -> Binding<String> {
        Binding(
            get: { context[keyPath: keyPath] ?? "" },
            set: { val in
                context[keyPath: keyPath] = val.isEmpty ? nil : val
                save()
            }
        )
    }

    private var gradeBinding: Binding<String> {
        Binding(
            get: { context.gradeLevel ?? "" },
            set: { val in
                context.gradeLevel = val.isEmpty ? nil : val
                save()
            }
        )
    }

    private var learningStyleBinding: Binding<LearningStyle?> {
        Binding(
            get: { context.learningStyle },
            set: { val in context.learningStyle = val; save() }
        )
    }

    private var responseFormatBinding: Binding<ResponseFormat?> {
        Binding(
            get: { context.responseFormat },
            set: { val in context.responseFormat = val; save() }
        )
    }

    private func save() {
        UserContextManager.shared.save(context)
    }

    private func addSubject() {
        let s = newSubject.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !(context.subjects ?? []).contains(s) else { return }
        if context.subjects == nil { context.subjects = [] }
        context.subjects?.append(s)
        newSubject = ""
        save()
    }

    private func addNote() {
        let n = newNote.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if context.customNotes == nil { context.customNotes = [] }
        context.customNotes?.append(n)
        newNote = ""
        save()
    }

    private let gradeLevels = [
        "High School - Freshman",
        "High School - Sophomore",
        "High School - Junior",
        "High School - Senior",
        "College - Freshman",
        "College - Sophomore",
        "College - Junior",
        "College - Senior",
        "Graduate Student",
        "PhD Student",
        "Professional",
    ]
}

// MARK: - FlowLayout (tag-style wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
