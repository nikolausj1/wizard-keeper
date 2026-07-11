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
    @ObservedObject private var themeManager = ThemeManager.shared
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
    @ObservedObject private var themeManager = ThemeManager.shared

    /// Drives the Announcer section's Preview Voice/Stop toggle — observed
    /// so the label/icon flip live as the sample plays and finishes, same
    /// pattern as `GameView`'s Trends broadcast button.
    @ObservedObject private var announcer = AnnouncerPlayer.shared

    /// Toggle for the "Preview Voice" row: stops if a sample (or any other
    /// broadcast) is already playing, otherwise plays a short sample in the
    /// currently-selected voice and style.
    private func togglePreview() {
        if announcer.isPlaying {
            announcer.stop()
        } else {
            announcer.preview(voice: settings.announcerVoiceSelection, style: settings.announcerStyleSelection)
        }
    }

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
                    .listRowBackground(Color.cardSurface)
                Toggle("Trick total check", isOn: $settings.trickTotalCheckEnabled)
                    .listRowBackground(Color.cardSurface)
            } header: {
                Text("House Rules")
                    .foregroundStyle(Color.paperSecondary)
            } footer: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bids can't total the tricks in a round.")
                        .foregroundStyle(Color.paperSecondary)
                    Text("Warn when tricks entered don't match the cards dealt.")
                        .foregroundStyle(Color.paperSecondary)
                    Text("Rule changes apply to new games — games in progress keep the rules they started with.")
                        .foregroundStyle(Color.paperSecondary)
                }
            }

            Section {
                Toggle("Full length", isOn: fullLengthBinding)
                    .listRowBackground(Color.cardSurface)
                if !settings.useFullLength {
                    Stepper(
                        "Default rounds: \(settings.customRoundCount ?? 10)",
                        value: customRoundCountBinding,
                        in: 1...20
                    )
                    .listRowBackground(Color.cardSurface)
                }
            } header: {
                Text("Game Length")
                    .foregroundStyle(Color.paperSecondary)
            } footer: {
                Text("Full length deals 60 \u{00F7} players cards per game.")
                    .foregroundStyle(Color.paperSecondary)
            }

            Section {
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    .listRowBackground(Color.cardSurface)
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .listRowBackground(Color.cardSurface)
                Picker("Theme", selection: $settings.appThemeSelection) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .onChange(of: settings.appThemeSelection) { _, newValue in
                    ThemeManager.shared.theme = newValue
                    modelContext.saveNow()
                }
                .listRowBackground(Color.cardSurface)
            } header: {
                Text("Feel")
                    .foregroundStyle(Color.paperSecondary)
            } footer: {
                Text("Theme and Appearance combine — pick a color theme, then light or dark within it.")
                    .foregroundStyle(Color.paperSecondary)
            }

            Section {
                Picker("Voice", selection: $settings.announcerVoiceSelection) {
                    ForEach(AnnouncerVoice.allCases) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }
                .onChange(of: settings.announcerVoiceSelection) { _, _ in modelContext.saveNow() }
                .listRowBackground(Color.cardSurface)
                Picker("Style", selection: $settings.announcerStyleSelection) {
                    ForEach(AnnouncerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: settings.announcerStyleSelection) { _, _ in modelContext.saveNow() }
                .listRowBackground(Color.cardSurface)
                Button(action: togglePreview) {
                    Label(
                        announcer.isPlaying ? "Stop" : "Preview Voice",
                        systemImage: announcer.isPlaying ? "stop.fill" : "speaker.wave.2.fill"
                    )
                }
                .listRowBackground(Color.cardSurface)
            } header: {
                Text("Announcer")
                    .foregroundStyle(Color.paperSecondary)
            } footer: {
                // Spicy (buckets 4-5) uses mild-to-real profanity — strip it
                // before any App Store submission (see `AnnouncerStyle`'s
                // doc comment in Announcer.swift).
                Text("Spicy is for adult tables.")
                    .foregroundStyle(Color.paperSecondary)
            }

            Section {
                LabeledContent("Version", value: "0.1.0")
                    .listRowBackground(Color.cardSurface)
                Text("Made for family game night")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.cardSurface)
            } header: {
                Text("About")
                    .foregroundStyle(Color.paperSecondary)
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
    .tint(.feltGreen)
    .modelContainer(for: [Player.self, Game.self, Round.self, AppSettings.self], inMemory: true)
}
