import SwiftUI
import AVKit

struct PlayerScreen: View {
    let video: Video
    /// Aynı videonun, yinelenen filtresinin gizlediği diğer sitelerdeki kopyaları
    let alternates: [Video]

    private enum LoadState {
        case loading
        case ready(PlaybackSource)
        case failed(String)
    }
    @State private var state: LoadState = .loading
    @State private var current: Video

    init(video: Video, alternates: [Video] = []) {
        self.video = video
        self.alternates = alternates
        _current = State(initialValue: video)
    }

    private var sources: [Video] { [video] + alternates }

    private func name(_ v: Video) -> String {
        ProviderRegistry.provider(v.providerID)?.displayName ?? v.providerID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                player

                if sources.count > 1 {
                    Menu {
                        ForEach(sources) { s in
                            Button { current = s } label: {
                                if s.id == current.id { Label(name(s), systemImage: "checkmark") } else { Text(name(s)) }
                            }
                        }
                    } label: {
                        Label("Kaynak: \(name(current)) (\(sources.count) sitede var)", systemImage: "arrow.triangle.branch")
                            .font(.subheadline)
                    }
                }

                Text(current.title).font(.headline)
                HStack(spacing: 12) {
                    if current.views > 0 { Label(Fmt.compact(current.views), systemImage: "eye") }
                    if current.rating > 0 { Label("%" + String(Int(current.rating)), systemImage: "hand.thumbsup") }
                    if current.durationSec > 0 { Label(Fmt.clock(current.durationSec), systemImage: "clock") }
                    if let d = current.addedAt { Label(d.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar") }
                }
                .font(.caption).foregroundStyle(.secondary)

                if !current.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(current.tags.prefix(25).enumerated()), id: \.offset) { _, tag in
                                Text(verbatim: tag).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    FavoritesStore.shared.toggle(video)
                } label: {
                    Image(systemName: FavoritesStore.shared.isFavorite(video) ? "star.fill" : "star")
                }
                .accessibilityLabel("Favori")
            }
        }
        .task(id: current.id) { await load() }
    }

    @ViewBuilder
    private var player: some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)

        case .failed(let message):
            VStack(spacing: 10) {
                ContentUnavailableView("Oynatılamadı", systemImage: "exclamationmark.triangle",
                                       description: Text(verbatim: message))
                ForEach(sources.filter { $0.id != current.id }) { other in
                    Button("\(name(other)) kaynağını dene") { current = other }.buttonStyle(.bordered)
                }
            }

        case .ready(.streams(let variants, let headers)):
            NativePlayerView(variants: variants, headers: headers)
                .id(current.id)

        case .ready(.embed(let url, let referer)):
            VStack(alignment: .leading, spacing: 4) {
                LockedEmbedView(url: url, referer: referer)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .id(current.id)
                Label("Bu kaynak yalnızca gömülü oynatıcı veriyor: kaliteyi oynatıcıdaki ⚙︎ menüsünden seç. Site açılmaz; çıkış linkleri ve açılır pencereler engelli.",
                      systemImage: "lock.shield")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        state = .loading
        let target = current
        guard let provider = ProviderRegistry.provider(target.providerID) else {
            state = .failed("Kaynak bulunamadı."); return
        }
        do {
            let source = try await provider.playback(for: target)
            guard target.id == current.id else { return }
            state = .ready(source)
            WatchHistory.shared.markWatched(video)   // "İzlediklerimi gizle" için
        } catch {
            guard target.id == current.id else { return }
            state = .failed(HTTP.describe(error))
        }
    }
}

/// Doğrudan akışlar için yerel oynatıcı + kalite menüsü.
struct NativePlayerView: View {
    /// "Otomatik" (yükseklik 0) ve/veya yüksekten düşüğe sabit kaliteler
    let variants: [StreamVariant]
    let headers: [String: String]

    @AppStorage("preferredQuality") private var preferred = 0
    @State private var player = AVPlayer()
    @State private var current: StreamVariant?

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if variants.count > 1 {
                    Menu {
                        ForEach(variants) { v in
                            Button { switchTo(v) } label: {
                                if v == current { Label(v.label, systemImage: "checkmark") } else { Text(v.label) }
                            }
                        }
                    } label: {
                        Label(current?.label ?? "Kalite", systemImage: "slider.horizontal.3")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(8)
                }
            }
            .onAppear { if current == nil, let v = initialVariant() { switchTo(v) } }
            .onDisappear { player.pause() }
    }

    /// Ayarlar'daki varsayılan kaliteye en yakın (onu aşmayan) seçenek.
    private func initialVariant() -> StreamVariant? {
        let fixed = variants.filter { $0.height > 0 }.sorted { $0.height > $1.height }
        let adaptive = variants.first { $0.height == 0 }
        guard preferred > 0 else { return adaptive ?? fixed.first }
        return fixed.first { $0.height <= preferred } ?? fixed.last ?? adaptive
    }

    private func switchTo(_ v: StreamVariant) {
        let position = player.currentTime()
        let options: [String: Any]? = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let item = AVPlayerItem(asset: AVURLAsset(url: v.url, options: options))
        player.replaceCurrentItem(with: item)
        if position.isValid, position.seconds > 1 {
            player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .positiveInfinity)
        }
        player.play()
        current = v
    }
}
