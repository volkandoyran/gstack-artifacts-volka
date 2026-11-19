#!/usr/bin/env python3
"""Derlenmiş IPA'yı web sitesinin ipa/ klasörüne koyar ve sürüm bilgisini (surum.json) yazar.

Kullanım:  python3 -I tools/ipa-surum.py <Vitrin.ipa> <site/ipa klasörü> [değişiklik notu]

surum.json, SideStore/AltStore kaynağı (/ipa/kaynak.json) ve kurulum sayfası tarafından okunur.
Çıkış kodu: 0 = IPA değişti ve yazıldı, 3 = aynı IPA zaten yerinde (yazılmadı).
"""
import hashlib
import json
import os
import plistlib
import shutil
import sys
import zipfile
from datetime import datetime, timezone


def info_plist(ipa_path):
    with zipfile.ZipFile(ipa_path) as z:
        names = [n for n in z.namelist() if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if not names:
            raise SystemExit('IPA içinde Payload/*.app/Info.plist bulunamadı')
        return plistlib.loads(z.read(names[0]))


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    ipa, out_dir = sys.argv[1], sys.argv[2]
    note = sys.argv[3] if len(sys.argv) > 3 else ''
    data = open(ipa, 'rb').read()
    sha = hashlib.sha256(data).hexdigest()

    old_path = os.path.join(out_dir, 'surum.json')
    if os.path.exists(old_path):
        try:
            if json.load(open(old_path, encoding='utf-8')).get('sha256') == sha:
                print('IPA değişmemiş:', sha)
                sys.exit(3)
        except ValueError:
            pass

    info = info_plist(ipa)
    surum = {
        'name': info.get('CFBundleDisplayName') or info.get('CFBundleName') or 'Vitrin',
        'bundleIdentifier': info['CFBundleIdentifier'],
        'version': info.get('CFBundleShortVersionString', '1.0'),
        'buildVersion': str(info.get('CFBundleVersion', '1')),
        'minOSVersion': info.get('MinimumOSVersion', '17.0'),
        'size': len(data),
        'sha256': sha,
        'date': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        'note': note,
    }
    os.makedirs(out_dir, exist_ok=True)
    shutil.copyfile(ipa, os.path.join(out_dir, 'Vitrin.ipa'))
    with open(old_path, 'w', encoding='utf-8') as f:
        json.dump(surum, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(json.dumps(surum, ensure_ascii=False))


if __name__ == '__main__':
    main()
