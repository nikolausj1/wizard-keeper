import SwiftUI

/// Shared sheet for creating a new saved `Player`: validates a non-blank,
/// case-insensitive-unique name and auto-assigns the next unused palette id.
/// Used by both `NewGameView` (seating flow) and `PlayersView` (roster "+").
struct AddPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let existingNames: [String]
    let nextColorId: Int
    let onAdd: (String, Int) -> Void

    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(attemptAdd)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: attemptAdd)
                }
            }
            .onAppear { nameFieldFocused = true }
        }
        .presentationDetents([.height(220)])
    }

    private func attemptAdd() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a name."
            return
        }
        guard !existingNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "A player named \u{201C}\(trimmed)\u{201D} already exists."
            return
        }
        onAdd(trimmed, nextColorId)
        dismiss()
    }
}

#Preview {
    AddPlayerSheet(existingNames: ["Justin", "Kelly"], nextColorId: 2) { _, _ in }
        .tint(.feltGreen)
}
