# Kısıtlama durumu ve itirazlar

26 Ekim 2026. Migration: 20261026084939_moderation_appeals, geliştirme ortamı.
Bu paket gerçek kullanıcıya yaptırım uygulamaz ve moderatör atamaz.

## Kullanıcı akışı

Doğrulanmış oturum açıldıktan sonra account_restricted sunucuda okunur. Aktif
kısıtlama varsa keşif yerine hesap durumu/itiraz ekranı açılır. Kullanıcı kendi
kısıtlamalarının planlanan bitişini, aktiflik durumunu, gönderdiği itirazı ve
kendisine yazılmış yanıtı görür. Rapor metni, şikâyetçi kimliği, moderatörün iç
gerekçesi veya başka kullanıcı bilgisi self-service yanıtına eklenmez.
Kullanıcıya ilk aşamada genel inceleme/kısıtlama açıklaması verilir; ayrıntılı,
kullanıcıya özel ilk karar gerekçesi ayrı bir alan olarak henüz yoktur.

Her kısıtlamaya bir itiraz: 5..2000 karakter, gönderildikten sonra değişmez.
Aynı metni tekrar gönderme ilk kaydı döndürür; farklı metin çatışma verir.
Geçmiş/süresi dolmuş/kaldırılmış kısıtlamalar için de itiraz edilebilir; ayrıca
son başvuru tarihi varsayılmadı. Veri miktarı moderatörün oluşturduğu vaka
sayısıyla sınırlıdır. Hesap ayarlarından geçmiş kayıt ve yanıtlar erişilebilir.
Kısıtlı ekranda yerel çıkış ve mevcut şifre doğrulamalı hesap silme sunulur.

## Yetki sınırı

appeal_actor doğrulanmış, anonim olmayan, silinmemiş ve Auth düzeyinde banlı
olmayan oturumu ve hesap silme kilidini kontrol eder. Yalnız uygulama kısıtlaması
self-service için istisnadır. Ana actor ve diğer uygulama RPC'leri gevşetilmedi.
Kendi kullanıcı kimliği auth.uid() ile türetilir; istemci hedef kullanıcı seçemez.
Ham sanction_appeals tablosu private şemada, RLS deny-all ve istemciye kapalıdır.
Yardımcı kimlik fonksiyonuna istemci execute yetkisi verilmez. Public invoker
RPC'leri açık parametre/rol/sahiplik kontrolleri yapan private definer'a gider.

## Moderatör akışı

Şikâyet inceleme ekranındaki İtirazlar düğmesi bekleyen/yanıtlanan kuyruğu açar.
Liste 20+1 keyset sayfalıdır. Kullanıcı kendi vaka tarafıysa moderatör de olsa
inceleyemez. İlk yaptırımı veren moderatör başka bir kullanıcıysa aynı operatör
itirazı inceleyebilir; zorunlu ikinci operatör politikası bu pakette yoktur.

Kararlar upheld (ilk karar korunur) / lifted (itiraz kabul edilir), kullanıcıya
5..1000 karakter açık yanıt gerekir. Kullanıcıya gösterildiği editörde belirtilir.
İtiraz kararı, inceleyen ve sunucu zamanı tek kez kaydedilir. Aynı aktör ve aynı
yanıt/karar tekrarı idempotent, farklı tekrar çatışmalıdır. Kabul ile ilgili
kısıtlamanın kaldırılması aynı transaction içindedir; başka aktif kısıtlama varsa
uygulama erişimi açılmaz. Önceden elle kaldırılmış kaydın kaldırma gerekçesi ve
aktörü değiştirilmez. Kararı korumak da kaldırılmış/süresi dolmuş kaydı yeniden
etkinleştirmez. Kilit sırası kısıtlama, sonra itirazdır.

Rapor/şikâyetçi silinince kısıtlama ve itiraz kalır; hedef hesap silinince kısıtlama
üzerinden itiraz da silinir. İnceleyen hesap silinirse reviewer_id null olur.
Bu ürün kayıtları haricî değiştirilemez denetim arşivi değildir.

## Ekran güvenliği ve bağlantı

AccountAccessGate kimliğe bağlı iç Navigator yönetir. Beş saniyede bir durum
okunur; kısıtlı/normal durum değişimi veya kontrol hatası eski ekran yığınını
(diyaloglar dahil) kaldırır. Doğrulama hatasında içerik gösterilmez; tekrar dene
ve çıkış vardır. İstemci kontrol aralığı sunucu güvenlik sınırı değildir.

Arka plan/inactive durumunda ekran yığını örtülür; dönüşte doğrulanmadan açılmaz.
Aynı erişim durumunda yığın korunur, böylece fotoğraf seçici gibi sistem ekranları
normal dönüş yapabilir. Önceki kontrolün gecikmiş yanıtı generation ile atılır.
İtiraz ekranı kendi verisini arka planda/erişim kaybında temizler. İç diyaloglar ve
doğum tarihi seçici iç Navigator'a bağlıdır. Testler örtülü sohbet ve açık
modalın kısıtlama sonrası kaldırılmasını da kontrol eder.

İtiraz listesi elle yenilenir ve işlem sonrasında yeniden okunur. Belirsiz yanıt
listeyi temizler; yeni metin göndermeden önce kayıt kontrolü istenir. Kabul sonrası
son kısıtlama da kalktıysa kapı ana ekrana döner; yanıt Hesap ayarları altında
okunabilir. Push/e-posta bildirimi ve operatör yanıt süresi garantisi yoktur.

## Doğrulama ve kalanlar

Yerel DB sözleşmeleri: sahiplik, iç not gizliliği, idempotent gönderme/karar,
atomik kabul, bağımsız kısıtlamalar, önceki kaldırma kaydının korunması, rol kaybı,
20+1 sayfalama, anonim/doğrulanmamış/Auth-banlı ret. Flutter testleri: gönderme,
moderatör yanıtı, yetki kaybı, belirsiz kayıt, açık ekran/diyalog temizliği,
arka plandan gecikmiş yanıt ve bağlantı hatası. Çok bağlantılı yarış, iki fiziksel
iPhone ve gerçek operatörle uçtan uca kabul ayrıca yapılmalıdır.

Sürüm öncesi açık: gerçek operatör seçimi, kullanıcıya özel ilk karar gerekçesi,
mesaj/fotoğraf kanıtı, saklama/itiraz operasyon politikası, bildirim tercihi,
gerçek SMTP ve cihaz kabulü, imzalı arşiv/TestFlight dağıtımı.
