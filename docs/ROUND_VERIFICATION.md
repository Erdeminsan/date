# Ortak tur doğrulama çekirdeği

Durum: Node/Deno doğrulama çekirdeği, Supabase paket kabul RPC’si ve Flutter
göndericisi eklendi. Paket migration’ı geliştirme ortamında uygulandı.
Sonuç servisi ve kalıcı ödül işlemi henüz bağlı değil; bilgi açmaz.

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
sabit tutulmalıdır. Oda input_protocol alanı migration ile sky-hop-input-v1 olarak sabitlendi.
Milisaniye dönüşümü floor(epoch * 1000) olarak DB→replay testinde doğrulanır.

## Paket kabulü ve istemci gönderimi

`submit_game_input(room, sequence, flaps)` aktörü oturumdan, zamanı veritabanından
alır. Sunucu aralığı sequence üzerinden türetir. Paketler private tabloda RLS
ile kapalıdır; istemcinin doğrudan SELECT/INSERT/UPDATE/DELETE izni yoktur.
Eşleşme çift kilidi altında katılımcı, hesap, engel, oda durumu, sürüm ve süre
tekrar kontrol edilir. Aynı sıra ve içerik ilk alım zamanını döndürür;
farklı içerik reddedilir. Önceki paket yoksa sıra atlanamaz. Her oyuncu için
en fazla 45 paket ve her pakette en fazla 120 flap saklanabilir. Bu depolama
sınırı genel HTTP istek taşkını önlemi değildir; gateway gözlemi ayrıca gerekir.

Flutter tamamlanan 120 tick aralıklarını 250 ms aralıklarla kontrol eder;
aynı anda tek istek gönderir, iki saniye yanıt alınmazsa aynı immutable paketi
tekrar dener. Paket başlangıcından beş saniye geçince iptal eder. Son paket
onaylanmadan gönderim tamamlandı demez; arka plan/hesap değişimi gönderimi
kapatır. Kapanan uygulamada paketler diske yazılmaz; bu tur ödül üretemez.

Migration: 20261025190155_game_input_packets, geliştirme ortamında uygulandı.
Güvenlik danışmanında yalnız private deny-all tablolarına ilişkin beş INFO
kaydı var; yeni paket tablosu bunlardan biridir. Açık istemci politikası bilerek yoktur.
[Danışman açıklaması](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

## Canlı sonuç entegrasyonu için kalan işler

1. Uygulanan paket kabulünün gerçek cihaz kabulü: oda/hesap/eşleşme kontrolü, server receipt,
   paket boyutu ve hız sınırı; unique(room, player, sequence). Aynı içerik retry
   ilk alım zamanını korur; değişen içerik reddedilir. Tamamlanmış aralık değişmez.
2. Uygulanan Flutter gönderiminin gerçek cihaz kabulü: tur boyunca bir saniyelik tamamlanmış aralıkları gönderir; başarısız
   gönderim süre sınırında aynı paketle tekrar denenir. Uzun kopuş ödülsüzdür.
3. Servis güvenilir paketleri okur, çekirdeği çağırır; sonuç yazarken eşleşme/oda
   kilidi altında erişimi tekrar kontrol eder. İptal/engel/unmatch yarışları
   başarıya çevrilemez. Sonuç ve kazananın ilerlemesi aynı transaction içinde
   bir kez yazılır; istemci bu tablolara yazamaz.
4. İlk galibiyet şehir, ikinci galibiyet ilgi alanları. Kaybeden/beraberlik/
   eksik tur ödül üretmez. Görünürlük yalnız ilgili aktif eşleşmeye bağlıdır.

Replay fiziksel olarak mümkün bir sonucu doğrular; bot kullanmadığını kanıtlamaz.
Çekirdeğin tekrarlanabilir çıktısı DB idempotency ve yetkilendirme yerine geçmez.

Sonuç servisi ve kazanan erişimi güncellemesi: [ROUND_RESULTS.md](ROUND_RESULTS.md).
