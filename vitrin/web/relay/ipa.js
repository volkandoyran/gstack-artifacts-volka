// IPA dağıtımı: SideStore / AltStore "kaynak" dosyasını (source) uygulamanın kendi adresiyle üretir.
// Kaynak, telefondaki SideStore/AltStore'a bir kez eklenir; yeni sürüm yayınlandıkça uygulama
// oradan güncellenebilir. Sürüm bilgisi derleme sırasında yazılan /ipa/surum.json dosyasından gelir.

const DESCRIPTION = 'Yetişkinlere yönelik (18+) video sitelerinin arama sonuçlarını tek listede toplayan kişisel uygulama. '
  + 'Kategoriler, birlikte arama, sıralama, yinelenen video filtresi ve siteyi açmadan oynatma.';

export function buildSource(origin, surum) {
  const icon = `${origin}/icon-512.png`;
  const version = {
    version: surum.version,
    buildVersion: surum.buildVersion,
    date: surum.date,
    size: surum.size,
    downloadURL: `${origin}/ipa/Vitrin.ipa`,
    minOSVersion: surum.minOSVersion,
    localizedDescription: surum.note || `Sürüm ${surum.version} (${surum.buildVersion})`,
  };
  return {
    name: 'Vitrin',
    identifier: 'app.vitrin.kaynak',
    subtitle: 'Kişisel uygulama kaynağı',
    iconURL: icon,
    website: `${origin}/ipa/`,
    tintColor: 'f43f5e',
    apps: [{
      name: surum.name || 'Vitrin',
      bundleIdentifier: surum.bundleIdentifier,
      developerName: 'Kişisel',
      subtitle: 'Video toplayıcı (18+)',
      localizedDescription: DESCRIPTION,
      iconURL: icon,
      tintColor: 'f43f5e',
      category: 'entertainment',
      versions: [version],
      // Eski SideStore/AltStore sürümleri için tek sürüm alanları
      version: version.version,
      versionDate: version.date,
      versionDescription: version.localizedDescription,
      downloadURL: version.downloadURL,
      size: version.size,
      appPermissions: { entitlements: [], privacy: {} },
    }],
    news: [],
  };
}
