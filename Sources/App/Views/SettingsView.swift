import SwiftUI
import SwiftData

/// Screen H: house rules, game length, and app-wide preferences. Reads and
/// writes the single `AppSettings` record directly (`AppSettings` is a
/// SwiftData model, so once fetched a `@Bindable` wrapper keeps every
/// toggle/stepper live-saved with no separate "save" step).
///
/// Invariant carried over from `RulesSnapshot`: changing these toggles only
/// affects games created after the change — a game already in progress
/// keeps the rules frozen into it at creation time. This view surfaces that
/// invariant to the user via a footer note rather than leaving it implicit.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?

    var body: some View {
        Group {
            if let settings {
                SettingsForm(settings: settings)
            } else {
                ProgressView()
            }
        }
        .task { loadSettings() }
    }

    private func loadSettings() {
        guard settings == nil else { return }
        settings = try? AppSettings.fetchOrCreate(in: modelContext)
    }
}

/// The actual form, split out so it can hold a `@Bindable` wrapper around
/// an already-fetched (non-optional) `AppSettings`.
private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext

    /// `customRoundCount` is `nil` whenever `useFullLength == true` (see
    /// the model's doc comment); this binding fills in the spec's default
    /// of 10 for display/editing and writes real values straight back.
    private var customRoundCountBinding: Binding<Int> {
        Binding(
            get: { settings.customRoundCount ?? 10 },
            set: { settings.customRoundCount = $0 }
        )
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(title: "Settings")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                Toggle("Dealer's hook", isOn: $settings.hookRuleEnabled)
                Toggle("Trick total check", isOn: $settings.trickTotalCheckEnabled)
                Toggle("Show dealer rotation", isOn: $settings.dealerRotationEnabled)
            } header: {
                Text("House Rules")
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bids can't total the tricks in a round.")
                    Text("Warn when tricks entered don't match the cards dealt.")
                    Text("Highlights whose deal it is each round.")
                    Text("Rule changes apply to new games — games in progress keep the rules they started with.")
                }
            }

            Section {
                Toggle("Full length", isOn: fullLengthBinding)
                if !settings.useFullLength {
                    Stepper(
                        "Default rounds: \(settings.customRoundCount ?? 10)",
                        value: customRoundCountBinding,
                        in: 1...20
                    )
                }
            } header: {
                Text("Game Length")
            } footer: {
                Text("Full length deals 60 \u{00F7} players cards per game.")
            }

            Section {
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
            } header: {
                Text("Feel")
            }

            Section {
                Picker("Voice", selection: $settings.announcerVoiceSelection) {
                    ForEach(AnnouncerVoice.allCases) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }
                .onChange(of: settings.announcerVoiceSelection) { _, _ in modelContext.saveNow() }
                Picker("Style", selection: $settings.announcerStyleSelection) {
                    ForEach(AnnouncerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: settings.announcerStyleSelection) { _, _ in modelContext.saveNow() }
            } header: {
                Text("Announcer")
            } footer: {
                Text("Vicious and Unhinged are for adults-only tables. Remove before App Store submission.")
            }

            Section {
                LabeledContent("Version", value: "0.1.0")
                Text("Made for family game night")
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .paperBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Toggling "Full length" on clears the custom round count back to nil
    /// (its documented rest state); toggling it off seeds a sensible
    /// default of 10 if nothing was set yet.
    private var fullLengthBinding: Binding<Bool> {
        Binding(
            get: { settings.useFullLength },
            set: { newValue in
                settings.useFullLength = newValue
                if newValue {
                    settings.customRoundCount = nil
                } else if settings.customRoundCount == nil {
                    settings.customRoundCount = 10
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .tint(.indigo)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
