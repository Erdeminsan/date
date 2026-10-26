# Şikâyet inceleme kuyruğu

20261026033013_moderation_review geliştirme ortamına uygulandı. Moderatör
üyeliği tablosu boş başlar; bu çalışma gerçek bir hesaba yetki vermedi ve
hiçbir gerçek kullanıcıya yaptırım uygulamadı.

## Erişim

Moderatör üyeliği app_private.moderators tablosundadır. Kullanıcı metadata'sı
veya istemci alanı yetki kaynağı değildir. Tablo RLS deny-all ve istemci
okuma/yazmasına kapalıdır. Yetki atama/kaldırma RPC’si yoktur; belirlenmiş
operatör hesabının doğrulanması ve yetkilendirilmesi ayrıca yapılmalıdır.
UI düğmesi yalnız erişim kontrolü olumluysa Hesap ayarları içinde görünür;
bu görünürlük güvenlik sınırı değildir. Her liste/karar RPC’si sunucuda aktif,
doğrulanmış, yasaklı olmayan aktörü ve üyeliğini kontrol eder.

İnceleme işlemi rol satırında shared lock alır. Yetki kaldırma bu transaction'ın
bitmesini bekler; sonraki istek reddedilir. Moderatör kendisinin şikâyetçi veya
şikâyet edilen olduğu vakayı listede göremez ve inceleyemez. Rapor kuyruğu
isimleri ve şikâyet metnini gösterir; e-posta, doğum tarihi, şehir, ilgi alanı
ve özel sohbet dökümü içermez. Mevcut kullanıcı şikâyet RLS'si genişletilmedi.

## Karar ve kayıt

Bekleyen/incelenen listeler keyset ile 20+1 kayıttır. Karar dismissed (işlem
gerekmiyor) veya escalated (ileri inceleme gerekli), gerekçe 5..1000 karakter.
Bu kararlar hesabı askıya almaz, içerik silmez ve bildirim göndermez.
İleri inceleme gerekli vakalar incelenen listede işaretlidir; yaptırım akışı
henüz bağlı değildir.

report_reviews bir rapor için tek kayıt saklar: karar, gerekçe, inceleyen UID
ve sunucu zamanı. Aynı aktör/karar/gerekçe tekrarı no-op; farklı karar çatışma
üretir. Uygulama rolü bu kaydı doğrudan değiştiremez/silemez. Yeni karar veya
itiraz için ayrı sürümlü işlem henüz yoktur. DB yöneticisi mutlak yetkilidir;
bu kayıt haricî, değiştirilemez bir denetim arşivi değildir.

Mevcut hesap silme politikası raporu cascade siliyorsa inceleme de silinir.
İnceleyen hesap silinirse reviewer_id null olur. Kalıcı hukuki saklama/itiraz
politikası bu paketle varsayılmadı; ürün politikası olarak ayrıca kararlaştırılmalı.

## Arayüz ve kabul

Kuyruk elle yenilenir ve karar sonrasında yeniden okunur. Beş saniyelik yetki
kontrolü; rol/oturum/ağ kaybında metinler temizlenir ve açık karar diyaloğu
kapanır. Arka plan da metinleri temizler. Belirsiz kayıt yanıtında liste
boşaltılır; tekrar okuma önceki kararın kaydedilip kaydedilmediğini gösterir.
Moderatör üyeliği verilmiş gerçek hesap ve iki cihaz testi henüz yapılmadı.

Açık işler: operatör seçimi, yaptırım/itiraz akışı, mesaj/fotoğraf kanıtı,
karar geçmişi ekranı, saklama politikası ve operasyonel bildirimler.

## Süreli kısıtlama — 26 Ekim güncellemesi

20261026082121_moderation_sanctions geliştirme ortamına uygulandı. İncelenen,
escalated rapordan moderatör 24 saat veya 7 gün uygulama erişim kısıtlaması
verebilir. Bunlar ilk operatör seçenekleridir; otomatik ceza politikası yoktur.
Gerekçe ve açık onay zorunludur. Kendi vakasına veya başka bir moderatöre
kısıtlama verilemez. Rol atama bu akışın parçası değildir.

Her rapor tek kısıtlama oluşturur. Aynı operatör/süre/gerekçe tekrarı ilk kaydı
döndürür; bitişi uzatmaz, kaldırılmış kaydı yeniden etkinleştirmez. Farklı istek
çatışma verir. Kaldırma ayrı aktör, gerekçe ve sunucu zamanı saklar; aynı kaldırma
tekrarı idempotenttir. Birden çok bağımsız aktif kayıt varsa biri kaldırıldığında
diğerleri geçerli kalır. Süre dolumu sorgu anında değerlendirilir, cron gerekmez.

Uygulama erişim kontrolü ve hedef görünürlüğü kısıtlamayı sunucuda kontrol eder.
Mevcut JWT ile yeni profil/keşif/eşleşme/sohbet/oyun istekleri de reddedilir.
Bu Supabase Auth oturumunu kapatmaz ve auth.users üzerinde ban yazmaz.
Başlamış transaction, indirilmiş görüntü veya önceden üretilmiş imzalı URL geri
alınmaz. Eşleşmeler/mesajlar silinmez; süre dolumu veya kaldırma sonrasında
normal erişim koşulları tekrar geçerlidir. Şifre sıfırlama ve mevcut güvenli
hesap silme servis akışı bu uygulama kısıtlamasıyla kapatılmaz.

Kısıtlamalar ayrı sekmede 20+1 keyset sayfalıdır. Rapor/şikâyetçi silinirse
ilişkileri null olur, kısıtlama listede kalır ve kaldırılabilir. Hedef hesabın
silinmesi kısıtlama kaydını siler. Operatör silinirse aktör alanı null olur.
Bu kayıtlar kalıcı haricî denetim arşivi değildir. Ham tablo RLS deny-all ve
istemci erişimine kapalıdır; RPC'ler her istekte rolü doğrular. Ekran arka plana
geçişte, oturum/yetki kaybında veya belirsiz yanıtta hassas içeriği temizler.

Oyun sonuçlarının servis RPC'sinde son kullanıcı auth.uid() bulunmaması da
karşılanır: istemciye açık olmayan account_active yardımcı fonksiyonu güvenilir
katılımcı kimliklerini doğrular. Public servis RPC'leri yalnız service_role'a
açıktır; Edge getUser ile doğruladığı aktörü iletir. Kısıtlı iki taraftan biri
varsa hazırlama/finalizasyon reddedilir. Testte servis rolünün JWT subject'i
boşaltılarak başarılı sonuç ve kısıtlı hesap reddi doğrulanır.

Bu paket kullanıcıya kısıtlama durumu ekranı, uygulama içi itiraz gönderimi veya
bildirim eklemez. Bunlar sürüm öncesi açık işlerdir. Moderatör atanmamıştır;
gerçek hesaba yaptırım uygulanmamıştır. Yerel DB testleri çok bağlantılı yarış
testi değildir; fiziksel cihaz/operatör kabulü ayrıca yapılmalıdır.

### Sonraki paket: kullanıcı itirazları

Kısıtlama durumu ve itiraz ekranları 20261026084939_moderation_appeals ile
bağlandı. Yukarıdaki tarihsel açık işlerin güncel durumu ve sınırlamalar için
MODERATION_APPEALS.md'ye bakın. Operatör ataması ve bildirimler hâlâ yoktur.

### Mesaj kanıtı

Seçili mesaj şikâyetleri artık sunucudan alınan metin ve zaman kopyasıyla
incelenebilir. Şikâyet ve itiraz ekranlarına bağlandı; fotoğraf kanıtı açık.
Yetki, veri ömrü ve kabul ayrıntıları MESSAGE_REPORT_EVIDENCE.md'de.
