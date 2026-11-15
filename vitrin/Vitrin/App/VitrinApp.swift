import SwiftUI
import AVFoundation

@main
struct VitrinApp: App {
    @AppStorage("ageConfirmed") private var ageConfirmed = false
    /// Son açık sekme hatırlanır (0 = Keşfet, 1 = Favoriler, 2 = Ayarlar)
    @AppStorage("selectedTab") private var selectedTab = 0

    init() {
        // Sessiz modda da ses gelsin.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            if ageConfirmed {
                TabView(selection: $selectedTab) {
                    BrowseView().tabItem { Label("Keşfet", systemImage: "square.grid.2x2") }.tag(0)
                    FavoritesView().tabItem { Label("Favoriler", systemImage: "star") }.tag(1)
                    SettingsView().tabItem { Label("Ayarlar", systemImage: "gearshape") }.tag(2)
                }
            } else {
                AgeGateView { ageConfirmed = true }
            }
        }
    }
}

struct AgeGateView: View {
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "18.circle.fill").font(.system(size: 72)).foregroundStyle(.red)
            Text("Yetişkin içerik").font(.title.bold())
            Text("Bu uygulama 18 yaş ve üzeri içindir. Devam ederek 18 yaşından büyük olduğunu ve bulunduğun yerde bu içeriğe erişimin sorumluluğunun sana ait olduğunu onaylıyorsun.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("18 yaşından büyüğüm", action: onConfirm)
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(32)
    }
}
