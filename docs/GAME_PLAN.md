# 1.0.0 oyun planı — Sky Hop

Durum: kazananın bilgi açması onaylandı; teknik tasarım ve uygulama aşamaları planlandı. Henüz çok oyunculu oda, sunucu skor doğrulaması veya
bilgi açma uygulanmadı. Mevcut `Round` / `FlightGame` yalnızca antrenmandır.

## Oyuncu akışı

Eşleşme → oyun daveti → kabul → iki oyuncunun hazır olması → ortak geri sayım
→ 45 saniyelik tur → sunucunun sonucu doğrulaması → sonuç ve izin verilen bilgi.
İki oyuncu aynı engel dizisinde kendi kuşunu kontrol eder. Birbirleriyle fiziksel
çarpışma yoktur. Esinlenme Flappy tarzıdır; görsel/ses/isimler özgün kalır.

İlk oyun 45 saniye; mevcut çarpışma sonrası 0,85 saniye toparlanma yaklaşımı
korunabilir. Geçilen engel puan verir. Sonuçta puan, çarpışma ve eşitlik açık
biçimde gösterilir. Sonuç kuralları sürümlenir; istemci sonucu tek başına yazamaz.

## Onaylanan oyun ödülü ve sohbet kuralı

Kullanıcı kararı (25 Ekim 2026): yalnız kazanan rakibinin sıradaki bilgisini
açar. İlk galibiyette rakibin şehri, ikinci galibiyette ilgi alanları açılır.
İlerleme her oyuncu için ayrı, ilgili eşleşmeyle sınırlıdır. Kaybeden bilgi
açmaz; eşitlikte iki tarafa da yeni bilgi verilmez. Her iki oyuncunun da
geçerli turu tamamlaması gerekir; yarım tur veya kopuş galibiyet ödülü üretmez.
Zaten açılmış alanlar yeniden ödül sayılmaz; aynı sonuç ikinci kez işlenemez.

Doğum tarihi ve e-posta oyun ödülü olmaz. Şehir/ilgi alanlarını oyunla açmak
kayıt/profil ekranında açıkça anlatılacak; yalnızca ilgili eşleşme erişebilir.
Onaylanan sohbet kuralı: eşleşme oluşunca iki taraf da mesajlaşabilir;
sohbet için oyun tamamlama veya galibiyet gerekmez. Eşleşmeden ayrılma ve
engelleme mesaj erişimini kaldırır.
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
5. Kazanana özel şehir → ilgi alanı ilerlemesi ve eşleşmeye özel alan erişimi.
   Kabul: A ilk kez kazanınca yalnız A, B'nin şehrini görür; B kazanırsa
   kendi ilk alanını açar. Eşitlik ve tekrar sonuç ilerlemeyi değiştirmez.
6. Oyun sonucu/sohbet bağlantısı, erişilebilirlik, küçük ekran ve performans testi.

Her aşamada üçüncü kullanıcı, yasaklı kullanıcı, engelleme sırasında devam eden
istek, silinen hesap, eski JWT, iki eşzamanlı bitiş, tekrar paket, değiştirilmiş
paket, geç paket, eşitlik ve ağ kesilmesi senaryoları çalıştırılacak.

Kabul: iki fiziksel cihaz aynı engel akışını görür; sunucu puanı istemciyle
uyuşur; istemci doğrudan skor/erişim yazamaz; geçersiz veya yarım tur bilgi
vermez; tekrar istek ikinci ödül oluşturmaz. Bu kabul geçmeden ortak oyun
1.0.0 kapsamında tamamlanmış sayılmaz.

Ortak fizik sözleşmesi ve bağımsız motor çalışması: [GAME_ENGINE.md](GAME_ENGINE.md).
