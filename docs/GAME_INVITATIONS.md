# Oyun daveti ve bekleme odası

Eşleşme kartı davet ekranını açar. Yalnızca eşleşmenin iki katılımcısı okuyabilir
ve işlem yapabilir. Davet gönderen kabul/ret veremez; iki taraf da iptal edebilir.
Davet 60 saniyede, kabul edilmiş bekleme odası 120 saniyede sona erer.
Kabul aynı oda için tekrarlandığında süre uzamaz. Bu sürüm ortak turu başlatmaz,
skor veya bilgi erişimi üretmez; kullanıcıya bu sınır açıkça gösterilir.

## Sunucu kuralları

`game_room_action` public invoker / private definer düzenini kullanır. Kimlik,
hesap uygunluğu, eşleşme ve engel kontrolleri sunucudadır. İşlemler engelleme
ile aynı çift kilidini alır, kilitten sonra eşleşmeyi tekrar okur. Kısmi unique
indeks her eşleşmede tek aktif oda sağlar. Aynı aktif davetin tekrar gönderilmesi
aynı odayı verir, otomatik kabul sayılmaz ve ikinci kota harcaması yapmaz.
İşlem oda ID’sine bağlıdır; eski odanın iptali yeni odayı değiştirmez.

Her kullanıcı son 24 saatte en fazla 20 yeni davet oluşturabilir. Özel olay
sayacı eşleşme silinse de kalır; hesap silinince silinir. Eski olaylar bir
sonraki davette temizlenir. İstemci tabloya doğrudan yazamaz. Engelleme ve
hesap silme eşleşme FK zinciriyle odaları siler; yasaklı/silinen hesaplara
ilişkin oda erişimi güncel hesap kontrolleriyle reddedilir.

Süre aşımı bir sonraki oda RPC isteğinde kalıcılaştırılır; cron yoktur. Bu
nedenle ham tablodaki status, son RPC’den sonra süresi dolan bir oda için eski
kalabilir. İstemci durum için RPC kullanır. Gelecek oyun başlangıcı endpoint’i
de veritabanı saatini ve son kullanma zamanını yeniden doğrulamalıdır.

## İstemci ve doğrulama sınırı

Ekran açıkken 3 saniyede bir yenileme vardır; bu Realtime veya push bildirimi
değildir. Arka planda ve hata sonrası polling durur; dönüşte/tekrar denemede
sunucu yeniden okunur. Hata eski işlem düğmelerini kaldırır. Bekleyen istekte
tekrar tıklama engellenir, dispose timer’ı kapatır.

DB sözleşme testleri katılımcı izolasyonu, sahip/kabul yetkisi, tekrar işlem,
eski oda ID’si, süre aşımı, yasak ve kota kontrollerini kapsar. Yerel PGlite
tek bağlantılıdır; gerçek iki bağlantı yarışı ve iki fiziksel cihaz kabulü
henüz yapılmadı. UI testleri kabulün tek gönderimi, hata sonrası eski durumu
kaldırma ve lifecycle/polling temizliğini kapsar.

Sonraki paket: hazır olma, sunucu zamanlı ortak başlangıç, sürümlü giriş
paketleri ve replay doğrulayıcı. Bunlar olmadan bu oda, çok oyunculu oyunun
tamamlandığı anlamına gelmez.

## Geliştirme dağıtımı

Migration `20261025180144` geliştirme projesine uygulandı. Canlı yetki kontrolü:
anon RPC çalıştıramıyor; authenticated RPC çalıştırabiliyor ama tabloya doğrudan
INSERT yapamıyor; oda tablosunda RLS açık. Güvenlik danışmanında yalnızca
`app_private.account_deletions`, `like_events` ve `game_invite_events` için
bilerek istemci politikası verilmeyen özel tablo INFO kayıtları bulunuyor.
[Açıklama](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Hazır olma ve ortak turun sonraki aşaması: [SHARED_ROUND.md](SHARED_ROUND.md).
