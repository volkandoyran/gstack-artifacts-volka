// Sabit barındırma (ör. GitHub Pages) için kurulum profilini dosya olarak üretir.
// Kullanım: node tools/profil-olustur.mjs <site klasörü> <uygulamanın adresi>
// (Cloudflare Worker'da buna gerek yok; profil /vitrin.mobileconfig adresinde kendiliğinden üretilir.)
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { buildProfile } from '../relay/profile.js';

const [siteDir, url] = process.argv.slice(2);
if (!siteDir || !/^https:\/\//.test(url || '')) {
  console.error('Kullanım: node tools/profil-olustur.mjs <site klasörü> <https://… uygulama adresi>');
  process.exit(1);
}
const icon = await readFile(path.join(siteDir, 'apple-touch-icon.png'));
await writeFile(path.join(siteDir, 'vitrin.mobileconfig'), buildProfile({ url, iconBase64: icon.toString('base64') }));
console.log('Profil oluşturuldu:', path.join(siteDir, 'vitrin.mobileconfig'), '→', url);
