# Ortak tur doğrulama çekirdeği

Durum: saf Node/Deno uyumlu modül ve testler. HTTP endpoint, migration,
istemci paket gönderimi veya canlı dağıtım içermez. Bilgi açmaz.

`supabase/functions/_shared/game-engine.mjs` tek JavaScript fizik kaynağıdır;
eski test yolu bunu yeniden dışa aktarır. Mevcut 16 Dart/JS golden vektörü
değiştirilmedi. `round-verifier.mjs` yalnız güvenilir depodan yüklenen oda ve
ilk sunucu alım zamanlarını taşıyan paketlerle çağrılmalıdır. İstemci JSON'u
bu fonksiyona doğrudan vermek güvenlik açığı olur.

## Girdi sözleşmesi: sky-hop-input-v1

- İki farklı oda katılımcısı, her biri 45 adet bir saniyelik paket.
- Sıra 0..44; başlangıç dahil, bitiş hariç 120 tick aralıkları; boş flap
  listesi de gönderilir. Böylece sessizlik tamamlanmış tur sayılmaz.
- Her paket yalnız kendi aralığındaki benzersiz, artan tamsayı tickleri içerir.
- İlk sunucu alım zamanı aralık bitişinden en fazla 250 ms önce, aralık
  başlangıcından en fazla 5 sn sonra olabilir. Zamanlar monoton olmalıdır.
- Sonuç yalnız awaiting_result durumunda, tur bitiminden itibaren 15 sn
  dolmadan hesaplanır. Geçmişin tamamını tur sonunda yüklemek reddedilir.
- Skor ve çarpışma replay ile hesaplanır. İstemci skor alanı kullanılmaz.
  Eşit skor beraberliktir; çarpışma sayısı beraberliği bozmaz.

Bunlar yeni protokolün test edilmiş başlangıç sınırlarıdır; fiziksel iki cihaz
ve gecikme testleriyle kabul edilmeden üretim hazır sayılmaz. Sunucunun tek
bir saat kaynağı kullanılmalı; DB timestamp dönüşümünde milisaniye kuralı
sabit tutulmalıdır. Oda inputProtocol alanı henüz veritabanında bulunmaz;
canlı entegrasyon migration'ı bunu açıkça sabitlemelidir.

## Canlı entegrasyon için kalan işler

1. Yetkili katılımcıdan paket kabulü: oda/hesap/eşleşme kontrolü, server receipt,
   paket boyutu ve hız sınırı; unique(room, player, sequence). Aynı içerik retry
   ilk alım zamanını korur; değişen içerik reddedilir. Tamamlanmış aralık değişmez.
2. Flutter tur boyunca bir saniyelik tamamlanmış aralıkları gönderir; başarısız
   gönderim süre sınırında aynı paketle tekrar denenir. Uzun kopuş ödülsüzdür.
3. Servis güvenilir paketleri okur, çekirdeği çağırır; sonuç yazarken eşleşme/oda
   kilidi altında erişimi tekrar kontrol eder. İptal/engel/unmatch yarışları
   başarıya çevrilemez. Sonuç ve kazananın ilerlemesi aynı transaction içinde
   bir kez yazılır; istemci bu tablolara yazamaz.
4. İlk galibiyet şehir, ikinci galibiyet ilgi alanları. Kaybeden/beraberlik/
   eksik tur ödül üretmez. Görünürlük yalnız ilgili aktif eşleşmeye bağlıdır.

Replay fiziksel olarak mümkün bir sonucu doğrular; bot kullanmadığını kanıtlamaz.
Çekirdeğin tekrarlanabilir çıktısı DB idempotency ve yetkilendirme yerine geçmez.
