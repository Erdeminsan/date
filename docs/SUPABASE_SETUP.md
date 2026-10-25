# Supabase 0.2 kurulumu ve kabul testi

## Durum

Atideis / playmatch projesi: `fzrfkejwnemtyxgbxxfc`, Frankfurt.
Şema uygulama isteği araç tarafından reddedildi. Bu PR canlı veritabanına
uygulanmış değildir. SQL yerel PostgreSQL uyumlu PGlite motorunda test edildi.
SQL'i canlıya uygulamadan giriş sonrası profil ekranı kurulum eksik hatası gösterir.

## Veritabanı

`supabase/migrations/20261025122511_account_matching_foundation.sql` ilk şemadır.
Supabase Dashboard > SQL Editor üzerinden dosyanın tamamı bir transaction içinde
çalıştırılabilir. Tercih edilen ekip akışı, Supabase CLI ile projeyi link edip
migration'ı `db push` ile uygulamaktır; komutların güncel seçeneklerini `--help`
ile doğrulayın. Bu migration yalnızca boş PlayMatch şemasına bir kez uygulanır.
Diğer Supabase projelerine uygulamayın. Veri taşıma veya yıkıcı değişiklik içermez.

Canlıya uygulama sonrası tablo/RLS kontrolü, security advisors ve iki gerçek
hesapla kabul testi gerekir. Yerel auth fixtures gerçek Supabase Auth yerine geçmez.

## E-posta / giriş

- Email provider ve Confirm email açık kalmalıdır.
- Varsayılan Supabase e-posta servisi geliştirme içindir; yetkili alıcı ve hız
  sınırlamaları vardır. İki farklı test kullanıcısına e-posta göndermeden önce
  Custom SMTP ayarını ve gönderen adresini tamamlayın.
- Auth > URL Configuration: kontrolünüzdeki bir doğrulama sayfasını Site URL
  olarak yapılandırın. Varsayılan localhost yönlendirmesi mobil kullanıcı için
  hazır bir dönüş akışı değildir.
- Bu sürüm e-posta bağlantısı açıldıktan sonra uygulamaya dönüp e-posta/şifreyle
  giriş yapmayı destekler. Otomatik uygulamaya dönüş/deep link ve şifre sıfırlama
  henüz yoktur. Güvenlik kontrolünü aşmak için Confirm email kapatılmamalıdır.
- Kayıt sonucunda hesap zaten varsa Supabase e-posta gizliliği için aynı yanıtı
  döndürebilir; kullanıcıya kesin hesap oluşturuldu iddiası gösterilmez.

## Flutter

Repo kökünde:

```bash
bash scripts/setup.sh
flutter run --dart-define-from-file=config/development.json
```

`config/development.json` proje URL'sini ve **publishable** istemci anahtarını
barındırır. Bu anahtar gizli değildir; veri güvenliğini RLS ve RPC yetkileri sağlar.
`service_role`, `sb_secret_...`, veritabanı şifresi ve Apple sertifikaları istemciye
veya repoya eklenmez. Kişisel ortam değişiklikleri için ignore edilen
`config/local.json` kullanın.

Bağımlılık `supabase_flutter: 2.12.0` olarak sabitlendi. Bu çalışma ortamında
Flutter bağımlılık kurulumu güvenlik incelemesinde durduğundan `pubspec.lock`
üretilmedi. İlk başarılı `flutter pub get` sonrasında bu dosyayı PR'a ekleyin;
bunu yapmadan tekrarlanabilir release build kabulü vermeyin.

Mevcut demo bağımsız çalıştırılabilir:

```bash
flutter run --dart-define=DEMO_MODE=true
```

Gerçek mod, boş veri durumunda sahte kullanıcı veya sahte eşleşme göstermez.
Antrenman skoru gerçek profil kilidi açmaz.

## İki hesapla kabul testi

1. A hesabıyla kayıt ol; e-postanı doğrula ve giriş yap.
2. Ad, 18+ doğum tarihi, şehir ve ilgi alanlarını kaydet.
3. Çıkış yapıp giriş yap: profil korunmalı.
4. B hesabıyla aynı adımları tamamla; keşfette A görünmeli.
5. B, A'yı beğensin: henüz eşleşme oluşmamalı.
6. A, listeyi yenilesin ve B'yi beğensin: eşleşme oluşmalı.
7. B, eşleşme listesini yenilesin: aynı eşleşme görünmeli.
8. Şehir/doğum tarihi/ilgi alanları diğer kullanıcıya API dahil görünmemeli.
9. Bir hesap diğerini engellesin: eşleşme kaldırılmalı ve her iki taraf
   birbirini keşfette görememeli. Beğeni API çağrısı da reddedilmeli.
10. Profil görünürlüğünü kapat: yeni beğeni gönderme/alma engellenmeli.
11. Şikâyet gönder: rapor sadece gönderen hesabın sorgusunda görünmeli.
12. Bağlantıyı kes: okunabilir hata ve tekrar dene işlemi görünmeli.

Bu sürüm otomatik Realtime yenileme yerine aşağı çekerek/yenile düğmesiyle
senkronize edilir. Keşfet sayfası bir istekte 40 profil, eşleşmeler 100 kayıt
ile sınırlıdır; geniş ölçekli sayfalama sonraki adımdır.

## Veri ve erişim tasarımı

| Alan | Erişim |
| --- | --- |
| profiles | Doğrulanmış ve profilini tamamlamış kullanıcılar; engel/görünürlük kontrolü |
| profile_details | Yalnızca sahibi; eşleşme özel verileri otomatik açmaz |
| likes | Yalnızca gönderen; ekleme yalnızca doğrulanan RPC ile |
| matches | Yalnızca katılımcılar; oluşturma yalnızca karşılıklı beğeni işleminde |
| blocks | Yalnızca engelleyen; eşleşme ve iki yönlü beğeniler kaldırılır |
| reports | Yalnızca gönderen; yönetici incelemesi dashboard üzerinden |

Tüm tablolar RLS kullanır. İstemciye doğrudan INSERT/UPDATE/DELETE verilmez.
`public` RPC'leri SECURITY INVOKER'dır. Gerekli kontrollü yetki yükseltmeleri
expose edilmeyen `app_private` içinde, sabit search_path ve doğrulanmış auth.uid
kontrolüyle yapılır. Postgres'in varsayılan PUBLIC EXECUTE yetkisi kaldırılır.
Like/block aynı çift kilidini kullanır; tekrar beğeni idempotenttir.
Doğum tarihi ilk kayıt sonrası değiştirilemez. Bu, kimlik/yaş belgesi doğrulaması değildir.

## Testler

```bash
flutter analyze
flutter test
cd tool/database-tests
npm ci --ignore-scripts
npm test
```

16 veritabanı sözleşme kontrolü yerelde geçti. Auth tabloları ve auth.uid test
fixtures'larıdır; e-posta, JWT doğrulama, gerçek RLS ortam ayarı ve eşzamanlı
iki ağ isteği testi değildir. Flutter yeni sürüm testleri henüz çalıştırılamadı;
Dart format/sözdizimi kontrolü ve git diff --check geçti.

## Yayın öncesi kalanlar

Fotoğraf Storage izinleri; iki kişilik oyun odası/başlangıç senkronizasyonu;
sunucuda skor doğrulama ve bilgi açma; gerçek mesajlaşma; Realtime;
şifre sıfırlama; hesabı silme ve oturum iptali; engeli kaldırma ekranı;
moderasyon iş akışı; gizlilik/koşullar; app icon ve iOS imzalama.
Bunlar tamamlanmadan herkese açık dating ürünü olarak yayınlanmamalıdır.
