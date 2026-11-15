import SwiftUI

struct BrowseView: View {
    @State private var model = BrowseModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Tür", selection: $model.kindFilter) {
                        ForEach(KindFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    categoryChips
                    controls

                    if let note = model.aiNote {
                        Label(note, systemImage: "sparkles").font(.footnote).foregroundStyle(.secondary)
                    }
                    if !model.failures.isEmpty { failureBanner }
                    if let summary = hiddenSummary {
                        Label(summary, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 14) {
                        ForEach(model.videos) { v in
                            NavigationLink(value: v) {
                                VideoCard(video: v, extraSources: model.alternates[v.id]?.count ?? 0)
                            }
                            .buttonStyle(.plain)
                            .onAppear { model.loadMoreIfNeeded(current: v) }
                        }
                    }

                    if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if model.videos.isEmpty {
                        ContentUnavailableView("Sonuç yok", systemImage: "film.stack",
                                               description: Text("Farklı kategori ya da kaynak dene."))
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Vitrin")
            .navigationDestination(for: Video.self) { v in
                PlayerScreen(video: v, alternates: model.alternates[v.id] ?? [])
            }
            .searchable(text: $model.freeText, prompt: "Ara (Türkçe ya da İngilizce)")
            .onSubmit(of: .search) { model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.expandWithAI() }
                    } label: {
                        if model.aiBusy { ProgressView() } else { Image(systemName: "sparkles") }
                    }
                    .disabled(model.aiBusy || model.freeText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Yapay zekâ ile etiketlere çevir")
                }
            }
            .refreshable { model.refresh() }
            .onChange(of: model.kindFilter) { model.refresh() }
            .onChange(of: model.selected) { model.refresh() }
            .onChange(of: model.combine) { if model.selected.count > 1 { model.refresh() } }
            .onChange(of: model.sort) { model.refresh() }
            .task { if model.videos.isEmpty { model.refresh() } }
        }
    }

    private var hiddenSummary: String? {
        var parts: [String] = []
        if model.hiddenDuplicates > 0 { parts.append("\(model.hiddenDuplicates) yinelenen") }
        if model.hiddenWatched > 0 { parts.append("\(model.hiddenWatched) izlenmiş") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + " video gizlendi"
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !model.selected.isEmpty {
                    Button { model.selected = [] } label: {
                        Label("Temizle", systemImage: "xmark").font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.red.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(model.visibleCategories) { c in
                    let on = model.selected.contains(c.id)
                    Button { model.toggle(c) } label: {
                        HStack(spacing: 4) {
                            if model.kindFilter == .all {
                                Image(systemName: c.kind == .hentai ? "sparkle" : "person.fill").font(.caption2)
                            }
                            Text(c.title)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            if model.selected.count > 1 {
                Picker("Birleştir", selection: $model.combine) {
                    ForEach(CombineMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Spacer()
            Menu {
                Picker("Sırala", selection: $model.sort) {
                    ForEach(SortOption.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            } label: {
                Label(model.sort.title, systemImage: "arrow.up.arrow.down").font(.subheadline)
            }
        }
    }

    private var failureBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.failures.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                Text(verbatim: "\(item.key): \(item.value)").font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct VideoCard: View {
    let video: Video
    var extraSources = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.secondary.opacity(0.15)
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: video.thumbnail) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    }
                }
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if video.durationSec > 0 { badge(Fmt.clock(video.durationSec), dark: true) }
                }
                .overlay(alignment: .topLeading) {
                    badge(sourceLabel, dark: false)
                }
                .overlay(alignment: .topTrailing) {
                    if let h = video.maxHeight { badge("\(h)p", dark: true) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(video.title).font(.footnote.weight(.medium)).lineLimit(2)
            HStack(spacing: 8) {
                if video.views > 0 { Label(Fmt.compact(video.views), systemImage: "eye") }
                if video.rating > 0 { Label("%" + String(Int(video.rating)), systemImage: "hand.thumbsup") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var sourceLabel: String {
        let name = ProviderRegistry.provider(video.providerID)?.displayName ?? video.providerID
        return extraSources > 0 ? "\(name) +\(extraSources)" : name
    }

    private func badge(_ text: String, dark: Bool) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(dark ? AnyShapeStyle(Color.black.opacity(0.75)) : AnyShapeStyle(.ultraThinMaterial),
                        in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(dark ? Color.white : Color.primary)
            .padding(5)
    }
}
