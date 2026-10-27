# Sunucuda bağımsız oyun sonucu — açık uygulama planı

Bu belge uygulama değildir. Mevcut finish-round hâlâ istemci isteğiyle çalışır
ve ilk sonuçlandırma için turun bitişinden sonra 15 saniyelik pencere vardır.

Kod incelemesinde birlikte değiştirilmesi gereken noktalar:
1. Son geçerli girdi paketleriyle transaction içinde kalıcı sonuç işi oluşturma.
   İki oyuncunun 90 sıralı paketi ve mevcut alım zamanı kontrolleri korunmalı.
2. Tam girdi bulunan turu kullanıcı arka plana geçti diye iptal etmemek.
   game_room_action süre aşımı ve cancel geçişleri aynı çift kilidi altında
   doğrulama kuyruğunu dikkate almalı. Eksik girdili turlar ödülsüz kapanmalı.
3. İşçi kısa lease ve yeniden deneme ile işleri almalı; bounded batch çalışmalı.
   DB source/receipt verileri mevcut JS verifyRound çekirdeğine verilmeli.
   Yeni bağımsız fizik motoru eklenmemeli.
4. verifyRound içindeki 15 saniyelik sonuç penceresi ile SQL prepare/finalize
   süre sınırları birlikte sürümlenmeli. Paket alım toleransı genişletilmemeli.
5. İşçi yetkisi istemci JWT'sinden ayrı olmalı. Cron/işçi kimliği ve gizli bilgi
   yönetimi kurulmalı; anahtar kaynak kodda veya cron komutunda açık tutulmamalı.
6. finalize çift kilidi altında engel, unmatch, hesap silme/kısıtlama ve tekil
   sonuç kaydını tekrar kontrol etmeli. İstemci ve işçi aynı anda tamamlayabilmeli.
7. Kuyruk yaşı, tekrar sayısı, başarısız işlerin izlenmesi ve temizliği tanımlanmalı.

Kabul: iki uygulama kapanınca tam girdili tur tek sonuç üretir; eksik/geç girdi
ödül üretmez; işçi çökmesi ve lease süresi sonrası retry ikinci ödül vermez;
engelleme/hesap silme yarışı erişimi veya ödülü geri açmaz.
Gerçek iki cihaz ve çok bağlantılı yarış testleri ayrıca gerekli.
