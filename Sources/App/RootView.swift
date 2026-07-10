import SwiftUI

/// Placeholder root. Real UI lands after the paper-aesthetic mockup pick
/// (PRD §7 mockups gate) — keep this visually neutral until then.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Wizard Keeper")
                .font(.largeTitle.bold())
            Text("Scaffold build — UI pending mockup approval")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
