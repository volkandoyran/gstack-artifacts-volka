import SwiftUI

struct FavoritesView: View {
    private var store: FavoritesStore { FavoritesStore.shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.videos.isEmpty {
                    ContentUnavailableView("Henüz favori yok", systemImage: "star",
                                           description: Text("Bir videoyu açıp sağ üstteki yıldıza dokunarak ekleyebilirsin."))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 14) {
                        ForEach(store.videos) { v in
                            NavigationLink(value: v) { VideoCard(video: v) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Favoriler")
            .navigationDestination(for: Video.self) { PlayerScreen(video: $0) }
        }
    }
}
