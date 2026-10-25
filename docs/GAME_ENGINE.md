# sky-hop-v1 fizik sözleşmesi

Durum: bağımsız Dart ve JavaScript motoru; mevcut antrenman ekranına ve canlı
oda servisine henüz bağlı değildir. JavaScript modülü Node/Deno uyumludur,
herhangi bir kullanıcı yetkilendirmesi veya ağ API’si içermez.

- Tur 5400 adımdır (120 Hz, 45 saniye). Girdi sıfır tabanlı adımın başında uygulanır.
- Konum birimi ekran yüksekliği/genişliğinin milyonda biridir. Hız 1/14400
  konum birimi/adım ölçeğinde saklanır; bölme sıfıra doğru kesilir.
- Yerçekimi adım başına 1350000 hız birimi, flap hızı -69600000.
- Engel her 198 adımda doğar; adım başına 2500 konum birimi ilerler.
- PRNG: unsigned 32-bit LCG, state = (1664525 * state + 1013904223) mod 2^32.
  Tohum 0 dahil 0..2^32-1. Merkez = 280000 + state mod 440001.
  Tüm ara çarpımlar JavaScript güvenli tamsayı aralığındadır.
- Çarpışma kuşu merkeze getirir; 102 adım boyunca flap ve puan verilmez.
- Aynı adımda çarpışma puandan önce değerlendirilir; kaçırılan engel puanlanmaz.
- Bitmiş motora yeni adım verilmesi sonucu değiştirmez.

`tool/game-tests/vectors.json` sabit uyumluluk verisidir. Dört tohum, hareketsiz,
periyodik, her adım flap ve otomatik pilot girişleri içerir. İki dil her saniye
bütün durumu karşılaştırır; yalnızca son skorun aynı olması yeterli değildir.
Üreteç bilerek CI’da çalışmaz: motor değişince beklenen verinin sessizce yeniden
üretilmesi yasaktır. Fizik değişikliği yeni engine_version ve gözden geçirilmiş
vektör gerektirir. Node testinde elle hesaplanan ilk adım da doğrulanır.

`replay` yalnızca sıralı, benzersiz, tur sınırları içindeki flap adımlarını
kabul eder. Bu, ağ güvenliği sağlamaz. Gelecek oda servisi kimlik/katılımcı,
engine_version, zaman penceresi, paket sırası ve idempotency kontrolünden sonra
saklanan girdileri bu motora verecek. İstemci skoru veya sonradan gönderilmiş
bütün oyun geçmişi tek başına kabul edilmeyecek.

Sonraki adımlar: antrenman adaptörü ve kare hızı testleri; oda/davet yaşam
döngüsü; zaman damgalı giriş paketleri; doğrulanmış sonuca bağlı kazanan ödülü.
