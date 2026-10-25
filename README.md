# PlayMatch

Flutter + Flame ile oyun üzerinden tanışma uygulaması. Geçici ürün adı PlayMatch.

## 0.2 — Supabase temeli

Gerçek e-posta/şifre oturumu, profil oluşturma/düzenleme, keşfet, karşılıklı
beğeniyle eşleşme, görünürlük, engelleme ve şikâyet kodu eklendi.
Şehir/doğum tarihi/ilgi alanları sadece sahibine açıktır. Oyun şu an antrenmandır;
gerçek profil bilgisi açmaz. Önceki çevrimdışı demo ayrı modda korunur.

**Durum:** Supabase şeması canlı projeye uygulandı. Altı tablonun RLS ve temel
yetkileri doğrulandı; security advisors uyarı döndürmedi. Yeni Flutter testleri
ve iki gerçek hesapla kabul testi henüz çalıştırılmadı. Bu dal geliştirme
incelemesi içindir; hazır bir üretim veya TestFlight sürümü değildir.

## Başlatma

```bash
git clone https://github.com/Erdeminsan/date.git
cd date
git switch feature/supabase-foundation
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

Dart format/sözdizimi ve `git diff --check` geçti. Yerel veritabanında 16 erişim
ve iş kuralı kontrolü geçti. Canlı Supabase RLS/yetki ve security advisor kontrolleri geçti.
Yeni Flutter analiz/widget testleri ve iki hesap kabul testi henüz çalıştırılmadı. Önceki 0.1 demoda 5 test kullanıcı Mac'inde geçmişti.

```bash
flutter analyze
flutter test
cd tool/database-tests
npm ci --ignore-scripts
npm test
```

## Geliştirme

Özellik dalları ve PR üzerinden ilerlenir. `pubspec.lock` başarılı ilk bağımlılık
çözümlemesinden sonra repoya eklenmelidir; henüz üretilmedi.
Publishable Supabase anahtarı istemci konfigürasyonudur; servis anahtarı ve Apple
imzalama sırları repoya girmez. Platform projelerini `scripts/setup.sh` üretir.

## Yol haritası

- [x] Yerel demo, oyun ve testleri
- [x] Supabase hesabı/projesi
- [x] Auth/profil/eşleşme Flutter kodu ve RLS migration
- [x] Migration canlı projede; RLS/yetkiler ve security advisors doğrulandı
- [ ] İki gerçek hesapla kabul testi
- [ ] Flutter analiz/test ve lockfile doğrulaması
- [ ] Fotoğraf, oyun odaları, senkron tur, sunucuda skor doğrulama
- [ ] Bilgi açma, mesajlaşma, Realtime
- [ ] Şifre sıfırlama, hesap silme, moderasyon ve gizlilik
- [ ] Fiziksel iPhone, imzalı arşiv ve TestFlight

Resmi referanslar: [Flutter iOS](https://docs.flutter.dev/deployment/ios),
[Supabase Flutter](https://supabase.com/docs/reference/dart/introduction),
[Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).
