# Profil fotoğrafını kanıt olarak şikâyet etme

26 Ekim 2026. Geliştirme migration'ı: 20261026183927_photo_report_evidence.
Edge: report-photo v1. Gerçek hesaplara yaptırım/yetki verilmedi ve gerçek
fotoğraflardan otomatik şikâyet oluşturulmadı.

## Akış

Keşif ve eşleşme menüsünde fotoğraf varsa Fotoğrafı şikâyet et görünür. Önizleme
mevcut özel profile-photos bucket'ından normal kullanıcı erişimiyle indirilir.
Kullanıcı 5..1000 karakter gerekçe ve gösterilen görüntüyle gönderimi onaylar.
İstemci görüntünün SHA-256 değerini ve tek istek UUID'sini gönderir; resim
verisini, hedefin kimliği dışında başka bir aktörü veya kaynak nesne ID'sini
kanıt olarak gönderemez. Fotoğraf kopyasının saklanacağı ekranda belirtilir.

Edge getUser ile bearer'ı doğrular; anonim/doğrulanmamış oturum reddedilir.
Service RPC çağrısındaki aktör yalnız bu doğrulanmış kimliktir. Hazırlık RPC'si
aktör/hedef hesap erişimi, aktörün profili, görünür hedef, karşılıklı engeller ve
fotoğrafın güncel yolunu doğrular. Kaynak Storage nesne UUID'sini döndürür.
Edge yalnız sabit profile-photos bucket'ında sunucudan gelen yolu indirir;
URL fetch veya istemci görseli yoktur. Boyut ve JPEG başlangıç/bitiş işaretleri
kontrol edilir; hash önizlemeyle eşleşmelidir. Bu tam bir JPEG içerik tarayıcısı
veya otomatik görüntü moderasyonu değildir.

Finalizasyon erişimi/kotayı ve kaynak nesne UUID'sini yeniden kontrol eder,
SHA-256'yı PostgreSQL'de de hesaplar. Fotoğraf değişmiş, silinmiş, yeniden aynı
yola yüklenmiş, gizlenmiş veya taraflar engelleşmişse yeni kayıt reddedilir.
Rapor ve kopya aynı transaction içinde yazılır. Aynı UUID/hedef/yol/hash/gerekçe
tekrarı ilk sonucu döndürür; değiştirilmiş tekrar çatışır. Önceki işlem
başarılıysa kaynak fotoğraf kaldırılmış olsa da aynı istek doğrulanabilir.

## Depolama tercihi ve sınırlar

Kopya ayrı app_private.report_photo_evidence tablosunda bytea olarak, en fazla
2 MiB tutulur. Böylece rapor ve hedef/şikâyetçi hesabı silinince kopya da aynı
cascade ile silinir; Storage kopyası/outbox temizliğine bağlı sahipsiz dosya yoktur.
Orijinal profil fotoğrafını değiştirme/silme kanıtı kaldırmaz. Üretim hacminde
bu kararın DB depolama/yedek ve aktarım maliyeti izlenmelidir: kayıt başına 2 MiB,
tek görüntüleme yanıtında base64 nedeniyle yaklaşık 2.8 MB üst sınırı vardır.
Büyük görüntü tabloları ana sorgulardan ayrıdır; listeler resim verisi döndürmez.

Genel şikâyetlerdeki mevcut 10 rapor/24 saat kotası paylaşılır. Bu kota mevcut
reports satırlarına dayanır; hedef hesabı silinmesi sonrası kota geçmişini
koruyan ayrı günlük henüz yoktur. Otomatik zaman bazlı saklama temizliği veya
haricî değiştirilemez arşiv eklenmedi. Kamuya açılmadan saklama/operatör politikası,
hacim ve çok bağlantılı yarış kabulü tamamlanmalıdır.

## Erişim ve ekranlar

Hazırlık/finalizasyon RPC'leri yalnız service_role'a açıktır. İstemci ham tabloya
okuma/yazma yapamaz. Gateway JWT kontrolü kapalıdır; bunun yerine fonksiyon her
istekte Auth getUser uygular. İstek gövdesi akış halinde 8 KiB ile sınırlandırılır,
anahtarlar/SDK hataları yanıta yazılmaz. Yeni npm bağımlılığı yoktur; mevcut
supabase-js 2.118.0 sabit sürümü kullanılır. Flutter crypto 3.0.7, mevcut kilitli
sürümden doğrudan bağımlılığa alınmıştır.

Moderatör şikâyet ve itiraz listelerinde Fotoğraf kanıtını aç düğmesini görür.
Resim ayrı RPC ile, rol ve vaka tarafı denetiminden sonra indirilir. Kamuya açık
veya süreli imzalı URL üretilmez. Kullanıcının kendi itiraz/kısıtlama okuması
fotoğraf verisini veya referansını içermez. Beş saniyelik vaka erişimi kontrolü
rol kaldırılmasını ve raporun silinmesini yakalar; görüntü temizlenir. Arka plan,
oturum değişimi ve başarısız erişim de görüntüyü temizler; görüntü cache girdisi
evict edilir. Önceden indirilmiş veriyi veya işletim sistemi ekran görüntüsünü
geri alma garantisi yoktur.

Gönderim yanıtı belirsizse gerekçe/hash/UUID değiştirilmeden tekrar denenir.
Arka planda önizleme temizlense de onaylanmış aynı istek tekrar doğrulanabilir.
Bu metadata sadece ekran belleğindedir; uygulama kapanınca kalıcı retry kuyruğu
yoktur. Fotoğraf değişmişse kullanıcı profili yenileyerek tekrar seçim yapar.

## Doğrulama

DB: istemci service RPC reddi, kaynak erişimi ve değişimi, hash/boyut kontrolü,
atomik yazma, ortak kota, değişmez tekrar, fotoğraf silinmesi sonrası kanıt,
moderasyon rol/vaka sınırı, verisiz liste, itiraz referansı ve hesap cascade'i.
Edge: getUser, sahte aktör/görsel alanlarını yok sayma, sabit bucket/sunucu yolu,
8 KiB gövde, JPEG/boyut/hash, idempotent yanıt, kota ve hata redaksiyonu.
Flutter: yüklenmiş önizleme ve gerekçe zorunluluğu, hash gönderimi, belirsiz yanıt
tekrarı, arka plan sonrası aynı istek, eksik önizleme, vaka erişimi kaybı ve
gecikmiş resim yanıtının eski veriyi geri getirmemesi.

Gerçek kullanıcı ve operatörle iki iPhone uçtan uca kabulü henüz yapılmadı.
