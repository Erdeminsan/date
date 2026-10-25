# Supabase 0.3 kurulumu ve kabul testi

## Durum

Atideis / playmatch projesi: `fzrfkejwnemtyxgbxxfc`, Frankfurt.
Şema 25 Ekim 2026 tarihinde canlı projeye uygulandı. Altı tablonun RLS ayarı,
anonim SELECT ve istemci INSERT yasakları doğrulandı. Supabase security advisors
uyarı döndürmedi. Yerel PostgreSQL uyumlu PGlite testleri de geçti.

## Veritabanı

`supabase/migrations/20261025124139_account_matching_foundation.sql` ilk şemadır.
Bu dosya mevcut PlayMatch projesinde zaten uygulanmıştır; tekrar çalıştırmayın.
Dosya sürümü sunucunun migration geçmişindeki `20261025124139` ile eşleştirildi.
Yeni bir boş geliştirme ortamına migration akışıyla uygulanabilir.

Canlı güvenlik kontrolleri tamamlandı; iki gerçek hesapla uçtan uca kabul testi
henüz yapılmadı. Yerel auth fixtures gerçek Supabase Auth yerine geçmez.

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

20 veritabanı sözleşme kontrolü yerelde geçti. Auth tabloları ve auth.uid test
fixtures'larıdır; e-posta, JWT doğrulama, gerçek RLS ortam ayarı ve eşzamanlı
iki ağ isteği testi değildir. Flutter yeni sürüm testleri henüz çalıştırılamadı;
Dart format/sözdizimi kontrolü ve git diff --check geçti.

## Yayın öncesi kalanlar

Fotoğraf Storage izinleri; iki kişilik oyun odası/başlangıç senkronizasyonu;
sunucuda skor doğrulama ve bilgi açma; gerçek mesajlaşma; Realtime;
şifre sıfırlama; hesap yönetiminin gerçek cihazda kabul testi;
moderasyon iş akışı; gizlilik/koşullar; app icon ve iOS imzalama.
Bunlar tamamlanmadan herkese açık dating ürünü olarak yayınlanmamalıdır.

## Hesap yönetimi (0.3)

`20261025125458_account_lifecycle.sql` canlı projede uygulanmıştır.
`blocked_profiles` yalnızca çağıranın engellediği kişilerin ad/id bilgisini verir.
`unblock_profile` yalnızca çağıranın engelini kaldırır. Eski beğeni/eşleşme
oluşturmaz ve karşı tarafın engelini kaldırmaz. Public RPC'ler invoker,
private fonksiyonlar actor kontrolü ile definer; anonim EXECUTE kapalıdır.
Canlı yetki sorgusu ve security advisors temizdir.

`delete-account` Edge Function v1 canlıdadır. `verify_jwt=false` yalnızca gateway
kontrolünü kapatır: fonksiyon gövdesi bearer tokenı `getUser` ile doğrular,
aynı hesabın şifresini Auth servisine yeniden doğrulatır, global refresh
session iptali başarılı olduktan sonra yalnızca doğrulanan kullanıcıyı hard-delete
eder. İstek gövdesindeki hedef id/e-posta kullanılmaz. Service-role anahtarı
sadece Edge ortamında kalır. Supabase JS sürümü 2.118.0 olarak sabittir.

Tablolardaki cascade ilişkileri profil, detaylar, beğeniler, eşleşmeler,
engeller ve şikâyet ilişkilerini temizler. Silinen hesaba ait eski access JWT
süresi dolana kadar kriptografik olarak geçerli olabilir; `actor()` silinen
Auth kaydını reddeder. Gelecekte Storage veya yeni tablolar eklenirse bu
silme/erişim tasarımı yeniden gözden geçirilmelidir.

Yerel Node testleri (10 senaryo) sahte Auth bağımlılıklarıyla çalışır:

```bash
node --test tool/edge-tests/delete-account.test.mjs
```

Canlı servise oturumsuz istek 401 AUTH_REQUIRED döndürdü. Gerçek hesabı silen
uçtan uca test yapılmadı; testlerin geçmesi SMTP, gerçek JWT veya SDK ile
başarılı silme akışının doğrulandığı anlamına gelmez. Flutter diyalog testleri
eklendi, fakat bu ortamda çalıştırılamadı.

Kabul testi için yalnızca silinmesi amaçlanan bir test hesabı kullanın:

1. Ayarlar'da kendi engel listenizi görün; engeli kaldırın, eski eşleşme dönmemeli.
2. Diğer hesap da sizi engellediyse profil hâlâ erişilemez olmalı.
3. Hesap silmede Vazgeç ve hatalı şifre hesabı korumalı.
4. Doğru şifre ve SİL onayı hesabı silmeli, uygulama giriş ekranına dönmeli.
5. Eski cihaz oturumu uygulama verisine erişememeli; profil ve ilişkiler silinmeli.
6. Silme servisi hata verirse başarı mesajı gösterilmemeli. Oturum iptalinden
   sonra silme başarısız olduysa kullanıcı tekrar giriş yapıp deneyebilir.

Şifre sıfırlama ve mobil doğrulama bağlantısı bu sürümün kapsamına dahil değildir.
