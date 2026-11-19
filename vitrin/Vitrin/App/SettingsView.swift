import SwiftUI

struct SettingsView: View {
    // Video
    @AppStorage("preferredQuality") private var quality = 0
    // Filtreler
    @AppStorage(FilterSettings.dedupeKey) private var dedupe = DedupeLevel.normal.rawValue
    @AppStorage(FilterSettings.hideWatchedKey) private var hideWatched = false
    @State private var watchedCount = WatchHistory.shared.count
    // Kaynaklar
    @State private var disabled = ProviderRegistry.disabledIDs
    @State private var customSites = ProviderRegistry.customSites
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var newLanguage = Lang.tr
    @State private var addError: String?
    // Yapay zekâ
    @AppStorage(AIConfig.engineKey) private var engine = AIEngine.auto.rawValue
    @AppStorage(AIConfig.geminiModelKey) private var geminiModel = AIConfig.defaultGeminiModel
    @AppStorage(AIConfig.gptBaseKey) private var gptBase = AIConfig.defaultGPTBase
    @AppStorage(AIConfig.gptModelKey) private var gptModel = AIConfig.defaultGPTModel
    @State private var geminiKey = Keychain.get(AIConfig.geminiSecret) ?? ""
    @State private var gptKey = Keychain.get(AIConfig.gptSecret) ?? ""
    @State private var gptNote = AIConfig.gptPresets[0].note

    var body: some View {
        NavigationStack {
            Form {
                videoSection
                filterSection
                sourcesSection
                addSiteSection
                aiSection
                geminiSection
                gptSection
                Section("Ağ, DNS ve VPN") {
                    Text("Uygulama kendi DNS'ini veya proxy'sini kullanmaz; iOS'taki DNS profilin ve VPN'in neyse onu kullanır, onları engellemez. Bir kaynak engelliyse hata mesajında belirtilir — VPN/DNS'i açıp listeyi aşağı çekerek yenile.")
                        .font(.footnote)
                }
                Section("Güvenlik") {
                    Text("Reşit olmayanları çağrıştıran içerikler (loli, shota, liseli vb.) her zaman filtrelenir ve bu ayar kapatılamaz.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Ayarlar")
            .onAppear { watchedCount = WatchHistory.shared.count }
        }
    }

    // MARK: Video

    private var videoSection: some View {
        Section {
            Picker("Varsayılan kalite", selection: $quality) {
                ForEach(QualityPreference.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } header: { Text("Video") } footer: {
            Text("Doğrudan akış veren kaynaklarda (XVideos, XNXX; akışı çıkarılabildiğinde Doeda gibi Türk siteleri) video uygulamanın kendi oynatıcısında açılır ve kalite menüsü oynatıcının sağ üstündedir. Yalnızca gömülü oynatıcı veren kaynaklarda (Pornhub, RedTube, Eporner) kalite o oynatıcının ⚙︎ menüsünden seçilir.")
        }
    }

    // MARK: Filtreler

    private var filterSection: some View {
        Section {
            Picker("Yinelenenleri gizle", selection: $dedupe) {
                ForEach(DedupeLevel.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("İzlediklerimi gizle", isOn: $hideWatched)
            Button("İzleme geçmişini temizle (\(watchedCount) video)", role: .destructive) {
                WatchHistory.shared.clear()
                watchedCount = 0
            }
            .disabled(watchedCount == 0)
        } header: { Text("Filtreler") } footer: {
            Text((DedupeLevel(rawValue: dedupe) ?? .normal).detail
                 + " Gizlenen kopyalar kaybolmaz: kartta “+1” olarak görünür ve oynatıcıdaki Kaynak menüsünden seçilebilir. İzleme geçmişi yalnızca bu cihazda tutulur.")
        }
    }

    // MARK: Kaynaklar

    private var sourcesSection: some View {
        Section {
            ForEach(ProviderRegistry.builtIn.indices, id: \.self) { i in
                providerToggle(ProviderRegistry.builtIn[i])
            }
            ForEach(customSites) { site in
                providerToggle(WordPressProvider(site: site))
            }
            .onDelete { offsets in
                customSites.remove(atOffsets: offsets)
                ProviderRegistry.customSites = customSites
            }
        } header: { Text("Kaynaklar") } footer: {
            Text("Kendi eklediğin siteleri sola kaydırarak silebilirsin.")
        }
    }

    private func providerToggle(_ p: any ContentProvider) -> some View {
        Toggle(isOn: Binding(
            get: { !disabled.contains(p.id) },
            set: { on in
                if on { disabled.remove(p.id) } else { disabled.insert(p.id) }
                ProviderRegistry.disabledIDs = disabled
            })) {
            VStack(alignment: .leading) {
                Text(verbatim: p.displayName)
                Text(verbatim: ([p.language == .tr ? "Türkçe" : "Yabancı"]
                                + (p.nativeQuality ? ["uygulama içi kalite"] : [])).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var addSiteSection: some View {
        Section {
            TextField("Site adı (isteğe bağlı)", text: $newName)
            TextField("Alan adı — örn. ornek.com", text: $newAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Picker("Arama dili", selection: $newLanguage) {
                ForEach(Lang.allCases) { Text($0.title).tag($0) }
            }
            Button("Siteyi ekle") { addSite() }
                .disabled(newAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            if let addError { Text(verbatim: addError).font(.caption).foregroundStyle(.red) }
        } header: { Text("Site ekle (WordPress)") } footer: {
            Text("Türk sitelerinin çoğu WordPress kullanır ve kod yazmadan eklenebilir: alan adını yazman yeter. Site bu yöntemi desteklemiyorsa aramada o kaynak için hata görürsün; o zaman silebilirsin. Alan adı değişen siteler için (ör. doeda → yeni adres) eskisini silip yenisini ekle.")
        }
    }

    private func addSite() {
        guard let site = WordPressSite.custom(name: newName, address: newAddress,
                                              language: newLanguage) else {
            addError = "Alan adı geçersiz görünüyor."
            return
        }
        guard !ProviderRegistry.all.contains(where: { $0.id == site.id }) else {
            addError = "Bu site zaten ekli."
            return
        }
        customSites.append(site)
        ProviderRegistry.customSites = customSites
        newName = ""
        newAddress = ""
        addError = nil
    }

    // MARK: Yapay zekâ

    private var aiSection: some View {
        Section {
            Picker("Motor", selection: $engine) {
                ForEach(AIEngine.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } header: { Text("Ücretsiz yapay zekâ") } footer: {
            Text("Arama kutusundaki ✨ düğmesi yazdığın tarifi (“sarışın olgun kadın masaj yapıyor”) etiketlere çevirir: yabancı sitelere İngilizce, Türk sitelerine Türkçe gönderilir. Anahtar girmezsen ya da servis yanıt vermezse yerleşik sözlük kullanılır. Not: ✨ kullandığında yazdığın metin seçtiğin yapay zekâ servisine gönderilir.")
        }
    }

    private var geminiSection: some View {
        Section {
            SecureField("Gemini API anahtarı", text: $geminiKey)
                .onChange(of: geminiKey) { Keychain.set(geminiKey, for: AIConfig.geminiSecret) }
            Picker("Model", selection: $geminiModel) {
                ForEach(modelChoices, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            TextField("Başka model adı", text: $geminiModel)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        } header: { Text("Gemini (Google)") } footer: {
            Text("Ücretsiz anahtar: aistudio.google.com → “Get API key”. Kart gerekmez; ücretsiz katmanda günlük istek sınırı vardır.")
        }
    }

    private var modelChoices: [String] {
        AIConfig.geminiModels.contains(geminiModel) ? AIConfig.geminiModels : AIConfig.geminiModels + [geminiModel]
    }

    private var gptSection: some View {
        Section {
            Menu("Hazır servis seç") {
                ForEach(AIConfig.gptPresets) { p in
                    Button(p.name) { gptBase = p.baseURL; gptModel = p.model; gptNote = p.note }
                }
            }
            TextField("API adresi", text: $gptBase)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("Model", text: $gptModel)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("API anahtarı", text: $gptKey)
                .onChange(of: gptKey) { Keychain.set(gptKey, for: AIConfig.gptSecret) }
        } header: { Text("GPT (OpenAI uyumlu)") } footer: {
            Text(verbatim: gptNote + " Anahtarlar cihazın Keychain'inde saklanır.")
        }
    }
}
