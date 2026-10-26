# Mesaj kanıtıyla şikâyet

26 Ekim 2026; geliştirme migration'ı: 20261026170452_message_report_evidence.
Bu paket gerçek kullanıcı verisinden şikâyet üretmez, moderatör atamaz ve
gerçek hesaba yaptırım uygulamaz. Fotoğraf kanıtı bu pakete dahil değildir.

## Kullanıcı akışı

Karşı tarafın mesaj kartındaki bayrak düğmesi seçilen mesajı ve saklama
bilgilendirmesini gösterir. Kullanıcı 5..1000 karakter gerekçe ile açıkça gönderir.
Kendi mesajlarında şikâyet düğmesi yoktur; sunucu da kendi mesajını reddeder.
Şikâyet başına tek mesaj vardır. RPC yalnız match/message kimliği ve gerekçe
alır; kanıt metni veya mesajın yazarı istemci tarafından gönderilemez.

Sunucu mevcut oturumu, profili, eşleşme üyeliğini, hesap erişimini ve engel
ilişkisini doğrular. Mesaj o eşleşmenin karşı tarafına ait olmalıdır. Metin ve
orijinal gönderilme zamanı public.messages tablosundan okunur; kayda alınma
zamanı sunucuda üretilir. Rapor ile snapshot aynı transaction'da yazılır.

## Tekrarlar ve kilitler

reporter/message benzersizdir. Aynı eşleşme, mesaj ve kırpılmış gerekçeyle tekrar
ilk rapor kimliğini döndürür. Farklı gerekçe/eşleşme REPORT_CONFLICT olur.
Şikâyet başarıyla oluşturulduktan sonra eşleşme kaldırılmış olsa bile sahibi
aynı isteği tekrar ederek yanıtı doğrulayabilir. Yeni kanıt oluşturmak ise canlı
eşleşme erişimi gerektirir. Bu tekrar yolu başkasına mesaj/rapor bilgisi vermez.

Kilit sırası reporter seed3, pair seed2, match satırı ve seçili mesaj shared
lock'udur. Profil şikâyetiyle aynı mevcut 10 rapor/24 saat bütçesi kullanılır.
Başarılı tekrar kotayı tüketmez. Bu kota hâlâ mevcut reports satırlarını sayar;
hedef hesap silinmesine dayanıklı ayrı kota geçmişi bu pakette eklenmedi.
Çok bağlantılı canlı yarış testi ayrıca gereklidir; yerel testler sıralı
transaction sonuçlarını doğrular.

## İnceleme ve veri ömrü

Snapshot app_private.report_message_evidence içinde tutulur; RLS deny-all ve
istemciden doğrudan okuma/yazma yoktur. Moderation reports v2 ve appeals v3
okumaları önce mevcut rol/vaka tarafı kontrollerini uygular, yalnız o sayfadaki
raporlara bağlı seçili mesajları döndürür. Operatör mesajı ve iki zamanı
şikâyet/itiraz kararından önce görür. Tüm sohbeti açan bir API eklenmedi.
Eski okuma RPC'leri korunur. Kanıtsız profil şikâyetleri normal çalışır.

Snapshot'ın sohbet veya mesaj tablosuna cascade bağı yoktur: engelleme veya
eşleşme kaldırma sohbeti silse bile inceleme kanıtı kalır. Rapor silinirse kanıt
silinir. Mevcut hesap silme kuralları şikâyetçi/hedef silinince raporu ve kanıtı
silir. İnceleyen operatörün hesabını silmek kanıtı kaldırmaz. Kullanıcının kendi
kısıtlama/itiraz okumasına kanıt alanı eklenmez. UI, veri yanlışlıkla modele
verilse de bu bileşeni yalnız moderatör ekranında gösterir.

Saklama süresi/otomatik süre sonu temizliği ve silinen hesaplar için ayrı hukuki
arşiv varsayılmadı. Operasyonel saklama politikası sürüm öncesi açık iştir.
Bu snapshot DB yöneticisine karşı değiştirilemez bir arşiv değildir.

## Arayüz ve doğrulama

Belirsiz gönderim yanıtında gerekçe, ekran açıkken aynı mesaja tekrar gönderim
için korunur. Erişim kaybı ve arka plan bunu temizler. Açık şikâyet diyaloğu
sırasında sohbet erişim kontrolü devam eder; hata diyaloğu ve geçmişi temizler.
Gecikmiş, arka plan öncesi okuma yanıtı generation kontrolüyle atılır. Diğer
kapalı/örtülü ekranlarda olağan sohbet sorgulaması durur. Ağ hatası sonrası
kullanıcı yeniden okuma yapabilir; ana erişim kapısı da yerinde kalır.

DB doğrulaması: yetkisiz sohbet/mesaj/kendi mesajı reddi, sunucudan snapshot,
tekrar/çatışma, ortak kota, unmatch sonrası kanıt ve idempotent yanıt, itirazda
moderatör görünürlüğü, self-service gizliliği, rol kaldırma ve hesap silme
cascade'i. Arayüz testleri: seçili mesaj/gerekçe, kendi mesajında düğme olmaması,
belirsiz yanıt tekrarı, açık diyalogda erişim kaybı, eski lifecycle yanıtı,
moderatör kanıt gösterimi ve kullanıcı ekranında kanıt gizleme.

Kalanlar: fotoğraf kanıtı, gerçek operatör ve cihaz kabulü, saklama/bildirim
operasyonu, SMTP kabulü ve imzalı TestFlight dağıtımı.
