# Ortak turun başlangıcı

Durum: sunucu zamanlı ortak başlangıç ve iki istemcinin aynı engellerde oynaması
uygulandı. Canlı giriş paketleri, sunucuda sonuç doğrulama, rakip skoru ve bilgi
ödülü henüz yoktur. Gösterilen bitiş skoru açıkça yerel skor olarak etiketlenir.

## Oda durumu

Kabul sonrası her katılımcı yalnız kendi hazır bilgisini işaretler. İkisi de
hazır olduğunda çift kilidi altında tek seed ve engine_version ile sunucunun
5 saniye sonrasına starts_at yazılır. ends_at tam 45 saniye sonrasıdır.
Tekrar hazır isteği zamanı/seed’i değiştirmez. Aynı eşleşmede countdown,
running ve awaiting_result durumlarında da yeni oda açılamaz.

Durum RPC çağrısında sunucu saatine göre countdown → running → awaiting_result
olur. Sonuç altyapısı bağlanana kadar tur bitiminden 15 saniye sonra oda expired
olur. Her iki katılımcı da aktif turu iptal edebilir; engelleme/ayrılma/hesap
silme odanın FK zinciriyle kaldırılmasını sürdürür. Saat/seed alanları istemci
UPDATE’ına açık değildir. Eski antrenman duraklatma kuralları ortak turda kullanılmaz.

## İstemci saati ve kesinti

Sunucu yanıtındaki zaman, istek gidiş-dönüş süresinin yarısı eklenerek yaklaşık
hizalanır; sonra Stopwatch kullanılır. Bu bir ağ gecikmesi tahminidir, iki fiziksel
ekranın aynı milisaniyede çizdiği iddiası değildir. 2 saniyeden uzun istek veya
başlangıca 2 saniyeden fazla gecikme turu iptal eder. Aynı seed/tick/input motoru
aynı sonucu verir. Kare gecikmesi kaçırılan fizik adımlarını tamamlar; 5 saniyeden
uzun foreground durması turu iptal eder. Cihaz duvar saatindeki değişiklikler
başlangıçtan sonra kullanılan monoton sayacı değiştirmez.

Oda durumu ortak ekran açıkken 2 saniyede bir doğrulanır; istek zaman aşımı
4 saniyedir. Hata, başka katılımcının iptali, erişim kaybı veya uygulamanın arka
plana geçmesi yerel turu durdurur ve sunucu iptali denenir. Sunucuya ulaşılamazsa
oda süre aşımı ile kapanır. Ani süreç sonlandırılmasında karşı tarafın anında
haberdar olması garanti değildir. Geçerli tur/ödül için gelecekte iki tarafın
girdileri ve sunucu sonucu zorunlu olacak; kopan oyuncu üzerinden ödül yoktur.

## Kabul sınırı

DB testleri yalnız bir oyuncunun hazır olması, üçüncü kullanıcı, tekrar hazır,
seed/zamanın değişmemesi, tek aktif oda ve zaman geçişlerini kapsar. Dart testleri
server tick hizası, farklı kare hızları, replay eşitliği, gecikmiş katılım,
uzun duraklama ve RTT sınırını kapsar. Oda UI testi ikinci hazır gönderimini engeller.
Gerçek iki cihaz gecikmesi, uygulama kesintileri ve oynanış kabulü hâlâ gereklidir.

Sonraki paket: sırayla gönderilen değiştirilemez giriş paketleri, canlı zaman
penceresi doğrulaması, sunucu replay ve tek seferlik sonuç; ardından yalnız
kazanana şehir/ilgi alanı erişimi. Bu paket 1.0.0 tamamlandı anlamına gelmez.

Geliştirme migration'ı: `20261025184644`. Mevcut oda RPC’sinin yetkileri korunur;
public wrapper invoker, ayrıcalıklı işlem özel şemadadır. Ham oda yazma istemciye
kapalıdır. Dağıtım sonrası kısmi indeks ve yeni alanlar ayrıca kontrol edildi.

## Girdi gönderimi güncellemesi

Yeni geliştirme paketi InputSender ile tamamlanmış bir saniyelik aralıkları
sunucuya gönderir. Bitiş ekranı son paketin onayını bekler. Paketlerin kaydı
sonuç doğrulandı anlamına gelmez; sonuç/ödül akışı henüz bağlı değildir.
Ayrıntılar: [ROUND_VERIFICATION.md](ROUND_VERIFICATION.md).
