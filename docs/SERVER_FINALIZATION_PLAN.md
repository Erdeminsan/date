# Sunucuda bağımsız oyun sonucu

Durum: kalıcı kuyruk ve sunucu işçisi uygulandı. Son geçerli paketle iki
katılımcının 90 paketi tamamlanınca aynı transaction içinde tek sonuç işi
oluşur. Son paket/transaction geri alınırsa iş de geri alınır. Eksik tur
kuyruğa girmez. Veri alım pencereleri ve mevcut oyun motoru değişmez.

## Sonuç ve iptal

Tam girdili oda awaiting_result durumuna alınır; ilk sonuçlandırma için
sunucunun 24 saatlik yeniden deneme süresi vardır. Bu, oyuncunun girdi
gönderme süresini uzatmaz. Tam girdili tur normal cancel isteğiyle iptal
edilmez; unmatch, block, hesap silme ve yaptırım erişim denetimleri korunur.
Henüz tam gönderilmemiş tur normal iptal/süre aşımı kurallarını izler.

İstemci finish-round ile hemen sonuç isteyebilir; uygulamalar kapalıysa
dakikalık zamanlayıcı işçiyi çağırır. İki yol aynı tekil sonuç tablosunu ve
mevcut JS verifyRound motorunu kullanır. Çift kilidi altında hesap/engel/oda
ve paketler yeniden kontrol edilir. Sonuç kaydıyla kuyruk işi completed olur.
Eşitlik ödülsüzdür; aynı turdan ikinci sonuç veya ödül oluşturulamaz.

## İşçi ve güven sınırı

process-game-result yalnız room_id ve x-job-token alır. Her teslimatta DB'nin
ürettiği rastgele UUID, özel iş kaydıyla service-only RPC içinde doğrulanır.
Anahtar oda, pending durumu ve teslim lease süresiyle sınırlıdır; yeniden
denemede değişir, sonuç/başarısızlıkta silinir. İstemci aktör veya skor seçemez.
HTTP yanıtı yalnız durum/hata taşır; profil bilgisi veya paket döndürmez.

Anahtar kalıcı ortak hizmet anahtarı değildir; kaynak kodda, cron komutunda
veya uygulama yapılandırmasında bulunmaz. pg_net'in dahili HTTP taşıma
tablosunda geçici olarak bulunur. Bu uzantının kendi SQL izinleri Supabase
tarafından yönetilir; net şeması Data API'ye açılmamalı ve onu okuyan bir
public RPC eklenmemelidir. Uygulamanın iş/config tabloları RLS deny-all ve
istemcilere kapalıdır. Dispatcher/claim işlevleri yalnız DB yöneticisine açıktır.
Sahte veya eski teslim anahtarı sonuç oluşturamaz.

## Zamanlayıcı ve yeniden deneme

pg_cron her dakika app_private.dispatch_game_results() çağırır. Etkin endpoint
app_private.game_result_worker_config içinde bulunur; boş/devre dışı config
ağ çağrısı yapmaz. Her çalıştırmada en fazla 10 iş seçilir; eşleşme kilidi
meşgulse atlanır. Her HTTP çağrısında tek tur replay edilir, timeout 10 saniyedir.
Teslim lease/retry aralığı 30, 60, 120, 240 ve en fazla 300 saniyedir.
pg_net taşıma kuyruğu kaybolsa bile kalıcı iş yeniden gönderilir.

Geçersiz replay terminal invalid_round hatasıyla, 24 saati aşan iş
deadline_exceeded ile kapanır; ödül verilmez. Yetki veya geçici servis
hataları deadline'a kadar yeniden denenebilir. Başarılı/başarısız iş geçmişi
7 gün sonra dispatcher tarafından temizlenir; asıl sonuç kayıtları silinmez.
Operatör alarm entegrasyonu ve yüksek yük kapasite kabulü ayrıca açıktır.

## Doğrulama

Yerel PostgreSQL testleri: 89 paket iş oluşturmaz; son paket atomik kuyruk
oluşturur; rollback, tekrar, normal cancel, eski 15 saniyelik pencereyi aşan
replay, lease/anahtar değişimi, yaptırım, geçersiz tur, deadline ve block cascade.
PGlite'da yalnız cron ve HTTP transport stublanır; gerçek dispatcher SQL'i çalışır.
Gerçek çok bağlantılı yarış ve fiziksel iki cihaz kabulü ayrıca gereklidir.

Geliştirme ortamında: görünmez, giriş bilgisi olmayan iki sentetik hesap ve
eski sonuç penceresini aşan tam paketli bir tur kullanıldı. Gerçek cron → pg_net
→ Edge → SQL zinciri ilk denemede HTTP 200 ile tek completed sonuç üretti.
Test hesapları, oda, iş ve sonuç cascade temizlendi. Bu sunucu zinciri testidir;
fiziksel cihaz, gerçek Auth veya insan oynanışı kabulü değildir.

## Operasyon kontrolleri

- cron.job ve cron.job_run_details: playmatch-game-results etkinliği/başarısı.
- game_result_jobs: status, attempts, next_attempt_at, last_error, last_request_id.
- net._http_response: ilgili request ID için status_code/timed_out/error_msg.
- Dağıtım sırası: güncel verifier kullanan finish-round ve process-game-result,
  kuyruk migration'ı, scheduler migration'ı, yönetici tarafından endpoint etkinleştirme.
- Acil durdurma: config.enabled=false; kuyruğun otomatik denemeleri durur.
  Mevcut istemci finish-round yolu çalışmaya devam eder.
