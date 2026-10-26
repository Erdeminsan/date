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
