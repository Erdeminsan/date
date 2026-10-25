# Profil fotoğrafları

Bu dalın kapsamı tek profil fotoğrafını galeriden seçme, değiştirme ve silmedir.
Çoklu albüm, kamera çekimi ve otomatik içerik moderasyonu kapsamda değildir.
Fotoğraf eklemek için önce profil kaydedilmiş olmalıdır.

## Dosya akışı

- image_picker 1.2.1, Flutter 3.38.0 ile uyumlu sürümdür; daha yeni picker
  sürümü daha yeni Flutter istediği için seçilmedi. image 4.12.0 sabittir.
- Galeri seçimi 1280 piksele sınırlandırılır. Uygulama ayrıca 12 MB giriş ve
  20 milyon piksel sınırı uygular, yönü düzeltir, en fazla 1024 piksel JPEG
  üretir. Yeni piksel görüntüsüne kodlama orijinal EXIF/konum metadatasını taşımaz.
- Sunucu bucket kısıtı JPEG içerik türü ve 2 MiB'dır. Dosya adları kullanıcı
  ID'si altında rastgele UUID v4'tür. Değiştirmede eski dosyanın üzerine yazılmaz.
- Özel bucket'tan yalnızca oturumla download yapılır; public veya kalıcı imzalı
  URL üretilmez. Bir fotoğrafın daha önce indirilmiş kopyası geri alınamaz.
- Supabase içerik-türü kısıtı gerçek piksel doğrulamasının veya moderasyonun
  yerine geçmez. Normal uygulama istemcisi görüntüyü yeniden kodlar; değiştirilmiş
  istemciden gelen dosyalar için sunucu içerik taraması henüz yoktur.

## Yetkiler ve eşzamanlı işlemler

Dosya ekleme yalnızca sahibinin klasörüne yapılır; kullanıcı başına en fazla
3 nesne tutulabilir (aktif fotoğraf ve değiştirme sırasında kalan dosyalar).
Yeni fotoğraf ilişkilendirildikten sonra eski dosya kaldırılır. Temizlik hatası
yeni fotoğrafı geri almaz. Fotoğrafı sil işlemi aktif ilişkiyi kaldırıp kalan
sahip dosyalarını da temizlemeyi dener.

Profil/engel/yasak RLS kontrolleri dosya okumasında da uygulanır. Fotoğraf adının
bilinmesi indirme izni vermez. Gizli profilin fotoğrafı diğer kişilere açılmaz.
Gecikmiş bir temizlik isteği o anda aktif olan fotoğrafı silemez.

Hesap silme servisi doğrulama ve şifre kontrolünden sonra özel bir silme kilidi
alır. Profil kaydı, fotoğraf ekleme ve değiştirme aynı kullanıcı kilidini
kullandığından dosya temizliği başladıktan sonra yeni yükleme tamamlanamaz.
Bu, henüz profil oluşturmamış hesapları da kapsar. Global oturum iptali ve
Storage API ile dosya temizliğinden sonra Auth hesabı silinir. Başarısızlıkta
kilit yalnızca ilgili istek tokenıyla geri alınır. Sunucu kesilirse 10 dakika
sonra yeni silme isteği kilidi devralabilir; eski istek yeni kilidi kaldıramaz.

Dosyalar temizlenip son hesap silme adımı başarısız olursa hesabın fotoğrafı
kaldırılmış olabilir; kullanıcı tekrar giriş yaparak silmeyi yeniden denemelidir.
Storage metadata'sı SQL DELETE ile silinmez; fiziksel dosya temizliği Storage
API üzerinden yapılır.

## Kabul sınırı

Yerel DB testleri Storage tablolarının uyumluluk fixture'larıyla RLS ve iş
kurallarını doğrular. Node testleri servis hata/temizlik sıralamasını doğrular.
Gerçek iPhone galeri izinleri, HEIC/JPEG/PNG seçimi, canlı Storage yükleme/indirme,
iki cihazda eşzamanlı fotoğraf değiştirme ve dosyalı hesap silme ayrıca denenmeli.
HEIC her ortamda çözülemez; seçici JPEG'e dönüştürmezse okunabilir hata gösterilir.
1.0.0 için bu gerçek cihaz kabulü tamamlanmış sayılmamıştır.
