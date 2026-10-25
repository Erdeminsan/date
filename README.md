# PlayMatch

Flutter + Flame ile oyun üzerinden tanışma uygulaması. Geçici ürün adı PlayMatch.

## 0.3 — Hesap yönetimi

Gerçek e-posta/şifre oturumu, profil oluşturma/düzenleme, keşfet, karşılıklı
beğeniyle eşleşme, görünürlük, engelleme ve şikâyet kodu eklendi.
Şehir/doğum tarihi/ilgi alanları sadece sahibine açıktır. Oyun şu an antrenmandır;
gerçek profil bilgisi açmaz. Önceki çevrimdışı demo ayrı modda korunur.

**Durum:** Supabase şeması canlı projede. GitHub Actions'ta Flutter analizi,
widget testleri ve Xcode 26 ile imzasız iOS release derlemesi geçti. İmzalı IPA,
fiziksel cihaz kabulü ve TestFlight yüklemesi henüz yok.

Ayarlar ekranında engellenen kişileri yönetme ve şifre + SİL onayıyla hesabı
kalıcı silme eklendi. Hesap silme servisi canlıda; gerçek hesapla uçtan uca
silme testi henüz yapılmadı.

TestFlight hazırlığı ve mevcut yayın engelleri: [TESTFLIGHT.md](docs/TESTFLIGHT.md).
Şifre sıfırlama ekranı ve native dönüş bağlantısı eklendi; dashboard redirect/SMTP
ayarları ve gerçek cihaz testi hâlâ gerekir. CI Flutter 3.38.0 ile çalışır.

## Başlatma

```bash
git clone https://github.com/Erdeminsan/date.git
cd date
git switch feature/testflight-readiness
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
