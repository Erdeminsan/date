# PlayMatch — 0.1.0 kaynak kod prototipi

Geçici isim: PlayMatch. Flutter uygulaması + Flame ile çizilen özgün Sky Hop oyunu.

## Bu paketin kapsamı

Çevrimdışı demo: isim/18+ onayı, üç kurgusal profil, demo beğeni/eşleşme,
45 saniyelik oynanabilir oyun, skor sonucu, şehir/ilgi alanı/sohbet kilitleri,
yalnızca ekranda kalan mesaj önizlemesi ve demo verilerini sıfırlama.
Fotoğraf ve diğer harici varlıklara ihtiyaç duymaz. İnternet bağlantısı kullanmaz.
Her uygulama yeniden açılışında bilgiler sıfırlanır. Gerçek hesap oluşturulmaz.

Gerçek multiplayer, sunucu, giriş sistemi, fotoğraf yükleme, karşılıklı gerçek
beğeni, kalıcı mesajlaşma, bildirim, moderasyon ve hesap silme henüz uygulanmadı.
Bu sürüm bitmiş dating uygulaması olarak veya gerçek kullanıcılarla eşleşiyor
şeklinde sunulmamalıdır. TestFlight'a yüklenmiş değildir.

## Mac'te ilk çalıştırma

Flutter stable SDK ve Xcode gereklidir. Xcode ilk kurulumunu ve iOS platform
bileşenlerini tamamlayın. Flutter SDK'nın Dart sürümü en az 3.5 olmalıdır;
bağımlılık çözümlemesi daha yeni Flutter isterse stable sürümü güncelleyin.

```bash
git clone https://github.com/Erdeminsan/date.git
cd date
flutter doctor -v
bash scripts/setup.sh
flutter devices
flutter run
```

Kurulum betiği yerel Flutter sürümünüzle iOS/Android platform projelerini üretir;
lib, test ve pubspec dosyalarını korur. ios klasörü varsa platform üretimini atlar.
Ardından bağımlılıkları indirir, formatlama, analiz ve testleri çalıştırır.
Oluşan pubspec.lock dosyasını projenin devamında saklayın/versiyonlayın.

## TestFlight için sonraki adım

Önce fiziksel iPhone'da tüm demo akışını deneyin. Bu ortamda Flutter/Xcode
bulunmadığından kod derlenmedi; eklenen testler burada çalıştırılamadı.
Kullanıcının Mac ortamında analiz ve 5 testin tamamının geçtiği doğrulandı (25 Ekim 2026); ekran testi telefon boyutu ve kaydırma için düzeltildi. Bu çalışma ortamında testler yeniden çalıştırılamadı. İmzalı iOS derlemesi ve TestFlight yüklemesi henüz doğrulanmadı.

```bash
open ios/Runner.xcworkspace
```

Runner > Signing & Capabilities: kendi Apple Developer Team'inizi seçin.
Bundle Identifier için `com.erdeminsan.playmatch` geçici öneridir; hesabınızda
kullanılabilirliğini kontrol edin ve gerekirse değiştirin. Display Name: PlayMatch.
Otomatik imzalamayı açın. Uygulamayı iPhone'da deneyin. Üretilen varsayılan
Flutter ikonlarını dağıtımdan önce özgün uygulama ikonu ile değiştirin.
App Store Connect'te aynı Bundle ID ile uygulama kaydı oluşturun.

```bash
flutter build ipa --release --build-name=0.1.0 --build-number=1
```

Arşiv: build/ios/archive/. IPA: build/ios/ipa/.
Arşivi Xcode ile açıp Validate App, ardından Distribute App > App Store Connect
adımlarını uygulayın veya IPA'yı Apple Transporter ile yükleyin.
TestFlight'ta build işleme tamamlandıktan sonra gerekli ihracat uyumluluğu
sorularını uygulamanın gerçek içeriğine göre yanıtlayın ve dahili test grubunu seçin.
Her yeni yüklemede build numarasını artırın. Harici test Apple beta incelemesine
tabidir; aynı gün onay garantisi yoktur.

Test notu önerisi: “Çevrimdışı PlayMatch prototipi. Tüm profiller kurgusaldır.
Keşfet → demo eşleşmesi → Sky Hop → bilgi açma akışını test edin.
Mesajlaşma yerel önizlemedir. Gerçek kullanıcı veya sunucu bağlantısı yoktur.”

## Oyun kuralları

3 saniyelik geri sayım; ardından 45 saniye. Dokunmak yükseltir, yerçekimi düşürür.
Engeli geçmek 1 puandır. Çarpma 0.85 saniye beklemeyle yeniden başlatır;
tur saati devam eder. Uygulama arka plana gidince durur ve dönüşte Devam et gerekir.
Demo rakip yerine sabit 3 puanlık hedef kullanılır; bu gerçek rakip skoru değildir.
3+ puan bir bilgi seviyesi açar. Seviye 1 şehir, 2 ilgi alanları, 3 sohbet önizlemesi.
Fizik 120 Hz sabit adımlı; engel dizisi seed ile üretilir. Gerçek multiplayer için
sunucu başlangıç zamanı, seed, bağlantı kopma kuralı ve sunucu skor doğrulaması gerekir.
İstemci skoruna güvenerek gerçek profil verisi açılmamalıdır.

## Kaynak düzeni

- lib/main.dart: uygulama ekranları ve geçici demo durumu.
- lib/game/round.dart: ekrandan bağımsız fizik ve skor kuralları.
- lib/game/flight_game.dart: Flame çizimi ve oyun döngüsü.
- test/: tur, deterministik adımlar, çarpışma, skor ve ekran akışı testleri.
- scripts/setup.sh: yerel platform oluşturma ve doğrulama.

## Gerçek beta için kalan işler

Backend seçimi ve proje kurulumu; kimlik doğrulama; sunucuda yaş/erişim kontrolü;
profil ve görsel depolama; kullanıcı bazında veri izinleri; karşılıklı beğeni;
oyun odaları ve aynı başlangıç zamanı; doğrulanan skor sonucu ve atomik bilgi açma;
gerçek mesajlaşma; engelleme/şikâyet ve moderasyon; gizlilik metni ve hesap silme.
18+ kutusu tek başına yaş doğrulama sistemi değildir. Kilitli profil verileri
sunucudan yetkisiz istemciye gönderilmemelidir.

## Resmi kaynaklar

https://docs.flutter.dev/deployment/ios
https://docs.flame-engine.org/latest/flame/game_widget.html
https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/

## Backend durumu

Atideis organizasyonunda Frankfurt bölgesinde PlayMatch Supabase projesi oluşturuldu.
Bu commit henüz Supabase entegrasyonu içermez; uygulama çevrimdışı demodur.
API anahtarları veya Apple imzalama bilgileri bu repoya eklenmemelidir.

## Geliştirme akışı

Yeni özellikler için `feature/` önekli dal açın; analiz ve testleri çalıştırıp PR üzerinden birleştirin.
Mac üzerinde oluşturulan platform projeleri ve pubspec.lock henüz bu kaynak paketinde yoktur.
`scripts/setup.sh` ile üretildikten sonra imzalama sırları hariç ilgili dosyalar versiyonlanmalıdır.
