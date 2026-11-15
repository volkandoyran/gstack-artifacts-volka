Kişisel kullanım için bir iOS uygulaması (SwiftUI, iOS 17+) geliştiriyorum ve bir sonraki sürüm için fikir danışmak istiyorum. Türkçe, kısa ve somut yanıt ver.

## Uygulama

Yetişkinlere yönelik (18+), yasal video sitelerinin arama sonuçlarını tek listede toplayan bir "video toplayıcı". İçerik barındırmaz, indirme yapmaz; yalnızca sitelerin herkese açık arama uç noktalarını/sayfalarını okur. App Store'a gönderilmeyecek, kullanıcı kendi telefonuna yan yükleyecek.

Şu an olanlar:
- 8 kaynak (JSON API'li siteler, HTML'i ayrıştırılan siteler, WordPress tabanlı Türk siteleri); her kaynak bir `ContentProvider` eklentisi. Kullanıcı Ayarlar'dan WordPress sitesi ekleyebiliyor.
- Kategoriler (çoklu seçim, VE / VEYA birleştirme), 6 sıralama ölçütü, sonsuz kaydırma.
- Türk sitelerine Türkçe, yabancı sitelere İngilizce arama terimi gönderen çevrimdışı sözlük.
- Oynatma: doğrudan akış (HLS) varsa AVPlayer + kalite menüsü; yoksa yalnızca oynatıcı çerçevesini gösteren, gezinmesi kilitli WKWebView (site açılmaz, pop-up ve reklam ağları engelli, çerez saklanmaz).
- Yinelenen video filtresi: başlık sadeleştirilir (küçük harf, aksanlar, anlamsız kelimeler atılır), kelime kümesi + süre karşılaştırılır (Jaccard ≥ 0.75 ve süre farkı ≤ %1). Gizlenen kopya "diğer kaynak" olarak saklanır.
- İzlenenleri gizleme (cihazda tutulan geçmiş).
- Reşit olmayanları çağrıştıran başlık/etiket/arama terimlerini her zaman eleyen, kapatılamayan güvenlik filtresi.
- Ağ: yalnızca varsayılan URLSession; kullanıcının DNS/VPN ayarına dokunulmaz.

## Sorular

1. Bu uygulamaya eklenebilecek en değerli 8 özelliği öncelik sırasıyla yaz. Her biri için: bir cümle ne olduğu, bir cümle neden değerli, zorluk (kolay/orta/zor).
2. Yinelenen video tespitini nasıl iyileştirirsin? Özellikle iki zor durum için pratik (cihazda çalışacak, sunucusuz) yöntem öner: (a) Türk sitelerinde video süresi yok, (b) aynı videonun başlığı başka dile çevrilmiş ya da tamamen yeniden yazılmış.
3. Gizlilik ve güvenlik açısından eksik gördüğün en önemli 3 şey nedir (ör. uygulama kilidi, geçmişin saklanması, ağ izleri)?
4. Mevcut tasarımda gördüğün en riskli teknik nokta nedir ve nasıl sağlamlaştırırsın?
