# 1.0.0 oyun planı — Sky Hop

Durum: tasarım önerisi. Henüz çok oyunculu oda, sunucu skor doğrulaması veya
bilgi açma uygulanmadı. Mevcut `Round` / `FlightGame` yalnızca antrenmandır.

## Oyuncu akışı

Eşleşme → oyun daveti → kabul → iki oyuncunun hazır olması → ortak geri sayım
→ 45 saniyelik tur → sunucunun sonucu doğrulaması → sonuç ve izin verilen bilgi.
İki oyuncu aynı engel dizisinde kendi kuşunu kontrol eder. Birbirleriyle fiziksel
çarpışma yoktur. Esinlenme Flappy tarzıdır; görsel/ses/isimler özgün kalır.

İlk oyun 45 saniye; mevcut çarpışma sonrası 0,85 saniye toparlanma yaklaşımı
korunabilir. Geçilen engel puan verir. Sonuçta puan, çarpışma ve eşitlik açık
biçimde gösterilir. Sonuç kuralları sürümlenir; istemci sonucu tek başına yazamaz.

## Kullanıcı kararı gereken ürün kuralları

Henüz onaylanmış sayılmayan öneri: iki kişi de doğrulanmış turu tamamladığında
birbirlerinin şehri; ikinci tamamlanan turda ilgi alanları açılır. Kazanan
skorla ayrıca gösterilir. Alternatif: bilgi açma yalnızca kazanana verilir.
Bu kural kesinleşmeden bilgi erişim migration'ı yazılmayacak.

Doğum tarihi ve e-posta oyun ödülü olmaz. Şehir/ilgi alanlarını oyunla açmak
kayıt/profil ekranında açıkça anlatılacak; yalnızca ilgili eşleşme erişebilir.
Sohbetin eşleşmede mi yoksa ilk turdan sonra mı açılacağı da kesinleştirilmeli.
1.0.0 için tek oyun Sky Hop'tur; başka mini oyunlar kapsamda varsayılmaz.

## Oda ve zaman yönetimi

| Durum | Geçiş ve kontrol |
| --- | --- |
| invited | Aktif eşleşme, engel/yasak yok; aynı eşleşmede tek aktif davet; önerilen süre 60 sn |
| ready | Davetli kabul eder; iki oyuncu ayrı hazır bildirir; süre aşımı iptal |
| countdown | Sunucu seed, engine_version ve starts_at üretir; önerilen geri sayım 5 sn |
| running | Süre sunucu saatine bağlıdır; uygulamayı duraklatmak süreyi durdurmaz |
| validating | Sunucu iki giriş akışını tekrar simüle eder; istemci skorunu kabul etmez |
| completed | Sonuç bir kez yazılır; seçilen kurala göre bilgi erişimi aynı işlemde verilir |
| cancelled / expired | Ret, engelleme, hesap silme veya süre aşımı; bilgi açılmaz |

Kısa bağlantı kesintisi için önerilen tolerans 5 sn. Giriş paketleri sıra
numarasıyla tekrar gönderilebilir; aynı sıra/farklı içerik reddedilir.
Uzun kopuş, uygulamanın arka planda kalması veya yalnızca bir kişinin bitirmesi
başarılı ortak tur sayılmaz. Kesin zaman pencereleri gerçek cihaz testinde
ayarlanacak. Otomatik galibiyet/bilgi ödülüyle kopuş istismarı oluşturulmayacak.

## Güvenilir sonuç için uygulama tasarımı

- `game_rooms`: eşleşme ve oyuncular, durum, seed, engine_version, sunucu zamanları.
- `game_inputs`: oyuncu, sıra numarası, tick aralığı ve flap tickleri. Katılımcı
  kontrolü, boyut/sıklık limiti ve zaman penceresi sunucuda yapılır.
- `game_results`: sunucunun hesapladığı puan/çarpışma; istemci INSERT/UPDATE yok.
- `profile_unlocks`: eşleşme, alan, açılma nedeni/turu; yalnızca doğrulanmış sonuç
  işlemi oluşturabilir. Engelleme/eşleşmeden ayrılma erişimi kaldırır.
- Realtime yalnızca davet, hazır olma ve sonuç güncellemelerini taşır. Broadcast
  ile gelen puan veya rakip hareketi yetkili sonuç kaynağı değildir.

Mevcut Dart `Random(seed)` algoritmasını JavaScript'te aynı varsaymayacağız.
Önce ortak bir engine_version, açık PRNG algoritması, sabit tick (120 Hz) ve
mümkün olduğunca tamsayı/fixed-point fizik tanımı hazırlanacak. Dart istemci ve
Edge doğrulayıcı aynı golden test vektörleriyle birebir sonuç vermeli.
Her tur sunucudan farklı seed alır. Giriş olayları tur boyunca küçük paketlerle
gönderilir; son anda bütün geçmişi değiştiren bir skor yüklemesi kabul edilmez.

Yeniden simülasyon fiziksel olarak mümkün sonucu doğrular; kişinin gerçekten
oynadığını veya bot kullanmadığını kanıtlamaz. Para/ödül ekonomisi yoktur;
bot tespiti ve kötüye kullanım gözlemi ayrı konudur. Bu tasarım “hile yapılamaz”
iddiası taşımaz.

## Geliştirme sırası ve kabul testleri

1. Ortak fizik/PRNG ve Dart–sunucu golden vektörleri; eski antrenman regresyonları.
2. Davet/oda RPC'leri ve RLS; iki cihazda kabul/ret/iptal, çift davet yarışı.
3. Sunucu saatiyle başlangıç, sürüm uyumu, mobil lifecycle/kopuş kurtarma.
4. Sıralı giriş paketleri, replay doğrulama, değiştirilemez/idempotent sonuç.
5. Onaylanan bilgi açma kuralı ve eşleşmeye özel alan erişimi.
6. Oyun sonucu/sohbet bağlantısı, erişilebilirlik, küçük ekran ve performans testi.

Her aşamada üçüncü kullanıcı, yasaklı kullanıcı, engelleme sırasında devam eden
istek, silinen hesap, eski JWT, iki eşzamanlı bitiş, tekrar paket, değiştirilmiş
paket, geç paket, eşitlik ve ağ kesilmesi senaryoları çalıştırılacak.

Kabul: iki fiziksel cihaz aynı engel akışını görür; sunucu puanı istemciyle
uyuşur; istemci doğrudan skor/erişim yazamaz; geçersiz veya yarım tur bilgi
vermez; tekrar istek ikinci ödül oluşturmaz. Bu kabul geçmeden ortak oyun
1.0.0 kapsamında tamamlanmış sayılmaz.
