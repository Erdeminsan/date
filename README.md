# PlayMatch

Flutter + Flame ile oyun üzerinden tanışma uygulaması. Geçici ürün adı PlayMatch.

## Güncel durum — fiziksel cihaz kabulü

Sürüm 0.3.0+3; 1.0.0 ve TestFlight dağıtımı henüz yapılmadı.
Kodda e-posta/şifre hesabı, özel profil fotoğrafı, yaş tercihli keşfet,
karşılıklı eşleşme, kalıcı sohbet, engelleme/şikâyet, hesap silme,
moderatör inceleme/yaptırım/itiraz ve mesaj/fotoğraf kanıtı bulunur.

Sky Hop davet, ortak başlangıç ve sunucuda doğrulanan iki kişilik tur içerir.
İlk galibiyet rakibin şehrini, ikinci galibiyet ilgi alanlarını açar;
doğum tarihi/e-posta açılmaz. Sohbet için oyun kazanmak gerekmez.
Tam gönderilmiş turlar uygulamalar kapalıyken de sunucu işçisiyle tamamlanır.
Önceki çevrimdışı demo ayrı modda korunur.

CI analiz/testleri ve imzasız iOS derlemesi başarılıdır; bu, imzalı IPA veya
gerçek cihaz kabulü değildir. SMTP/redirect, iki gerçek test hesabı, fiziksel
iPhone, moderatör operatörü ve mağaza/destek metinleri ayrıca doğrulanmalıdır.

- [Fiziksel cihaz test listesi](docs/DEVICE_ACCEPTANCE.md)
- [TestFlight araçlar, imzalama ve yükleme](docs/TESTFLIGHT.md)
- [1.0.0 kapsamı ve açık işler](docs/V1_SCOPE.md)
- [Sunucu sonuç işçisi](docs/SERVER_FINALIZATION_PLAN.md)

## Başlatma

```bash
git clone https://github.com/Erdeminsan/date.git
cd date
git switch main
bash scripts/setup.sh
flutter run --dart-define-from-file=config/development.json
```

Önce [Supabase kurulumunu](docs/SUPABASE_SETUP.md) tamamlayın. Hesap onayı için
SMTP/URL ayarları gerekir. İkinci bir gerçek hesap olmadan keşfet boş görünür.

Çevrimdışı demo:

```bash
flutter run --dart-define=DEMO_MODE=true
```

## Kaynaklar

- `lib/main.dart`: Supabase başlatma, oturum ve gerçek uygulama.
- `lib/backend/`: veri erişimi ve doğrulama.
- `lib/features/`: giriş, profil, keşfet/eşleşmeler.
- `lib/demo_app.dart`: önceki çevrimdışı demo.
- `lib/game/`: 45 saniyelik Sky Hop antrenmanı.
- `supabase/migrations/`: kontrollü RPC'ler, tablolar ve RLS.
- `tool/database-tests/`: yerel PostgreSQL erişim kontrolleri.
- `test/`: oyun, demo, auth formu ve model testleri.

## Doğrulama

GitHub Actions ilk yayın hazırlığı çalışmasında Flutter analizi/testleri, 20
veritabanı kontrolü, 10 servis testi ve platform yapılandırma testleri geçti.
iOS release derlemesi Xcode 26 ile imzasız olarak başarılı. Canlı SMTP/link,
iki hesap ve fiziksel cihaz kabulü ayrı doğrulanmalıdır.

```bash
flutter analyze
flutter test
node --test tool/edge-tests/delete-account.test.mjs
cd tool/database-tests
npm ci --ignore-scripts
npm test
```

## Geliştirme

Özellik dalları ve PR üzerinden ilerlenir. `pubspec.lock` CI çıktısından alınıp
repoya eklendi. Kurulum/CI kilitli bağımlılıkları doğrular.
Publishable Supabase anahtarı istemci konfigürasyonudur; servis anahtarı ve Apple
imzalama sırları repoya girmez. Platform projelerini `scripts/setup.sh` üretir.

## Yol haritası

- [x] Yerel demo, oyun ve testleri
- [x] Supabase hesabı/projesi
- [x] Auth/profil/eşleşme Flutter kodu ve RLS migration
- [x] Migration canlı projede; RLS/yetkiler ve security advisors doğrulandı
- [ ] İki gerçek hesapla kabul testi
- [x] Flutter analiz/test, lockfile ve imzasız iOS release derlemesi
- [ ] Fotoğraf, oyun odaları, senkron tur, sunucuda skor doğrulama
- [ ] Bilgi açma, mesajlaşma, Realtime
- [x] Engel listesi/kaldırma ve şifre doğrulamalı hesap silme kodu; servis canlıda
- [x] Şifre sıfırlama kodu ve native dönüş yapılandırması
- [ ] Gerçek cihaz auth kabulü, moderasyon ve gizlilik
- [ ] Fiziksel iPhone, imzalı arşiv ve TestFlight

Resmi referanslar: [Flutter iOS](https://docs.flutter.dev/deployment/ios),
[Supabase Flutter](https://supabase.com/docs/reference/dart/introduction),
[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

## 1.0.0 hedefi

Tüm temel özellikler ve kabul ölçütleri [V1_SCOPE.md](docs/V1_SCOPE.md) içinde.
1.0.0 henüz yayınlanmadı. İlk güvenlik düzeltmeleri beğeni limitinin engelleme
ile aşılmasını ve yasaklı hedeflerin keşfet/eşleşmelerde görünmesini kapatır.

Keşfet ve eşleşmeler artık 20 kayıtlık sayfalarla yüklenir. Eşleşme adları tek
sorguda gelir; Daha fazla ile devam edilir, Yenile ile ilk sayfaya dönülür.

Fotoğraf iş akışı: [PROFILE_PHOTOS.md](docs/PROFILE_PHOTOS.md).
Çok oyunculu oyun tasarımı: [GAME_PLAN.md](docs/GAME_PLAN.md).
