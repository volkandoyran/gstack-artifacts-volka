// iPhone'a "profil" olarak kurulan Web Clip yapılandırma profilini üretir.
// Profil, Ayarlar > Profil İndirildi > Yükle ile kurulunca ana ekrana tam ekran açılan
// uygulama simgesi ekler; Ayarlar > Genel > VPN ve Aygıt Yönetimi'nden kaldırılabilir.
// UUID'ler sabittir: profil yeniden kurulunca eskisinin yerini alır, kopya oluşmaz.

const xml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function buildProfile({ url, iconBase64, name = 'Vitrin' }) {
  const appURL = url.endsWith('/') ? url : `${url}/`;
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadIdentifier</key><string>app.vitrin.profil</string>
  <key>PayloadUUID</key><string>B7C1E2D3-5A4F-4B6C-9D8E-0F1A2B3C4D50</string>
  <key>PayloadDisplayName</key><string>${xml(name)}</string>
  <key>PayloadDescription</key><string>${xml(name)} uygulamasını ana ekrana ekler. Başka hiçbir ayarı değiştirmez.</string>
  <key>PayloadOrganization</key><string>Uygulamalarım</string>
  <key>PayloadRemovalDisallowed</key><false/>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.webClip.managed</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>app.vitrin.profil.webclip</string>
      <key>PayloadUUID</key><string>B7C1E2D3-5A4F-4B6C-9D8E-0F1A2B3C4D51</string>
      <key>PayloadDisplayName</key><string>${xml(name)}</string>
      <key>Label</key><string>${xml(name)}</string>
      <key>URL</key><string>${xml(appURL)}</string>
      <key>Icon</key><data>${iconBase64}</data>
      <key>FullScreen</key><true/>
      <key>IgnoreManifestScope</key><true/>
      <key>IsRemovable</key><true/>
      <key>Precomposed</key><true/>
    </dict>
  </array>
</dict>
</plist>
`;
}
