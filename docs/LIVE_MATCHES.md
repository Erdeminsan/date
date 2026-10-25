# Otomatik eşleşme güncellemesi

MemberHome, Eşleşmeler sekmesi görünür ve uygulama ön plandayken beş saniyede
bir mevcut matches RPC'sini çağırır. Diğer sekme, üst rota, kullanıcı işlemi,
sayfalama veya devam eden eşleşme sorgusu sırasında yeni polling başlatılmaz.
Sekmeye giriş ve uygulamaya dönüşte yenileme beklemeden başlar; üst rotadan
dönüşte en geç sonraki beş saniyelik aralıkta yenilenir.

Yenileme, kullanıcının yüklediği sayfa sayısı kadar baştan keyset sayfalarını
okur, tek bir yeni liste ve son sayfanın cursor'ını uygular. Eski listeye yalnız
ekleme yapılmadığı için kaldırılan eşleşmeler de silinir. Yeni eşleşmeler
önceki son kayıtları sonraki sayfaya taşıyabilir; yeni cursor bunlara erişimi
korur. Bir sayfa 20 kayıttır; yüklenen pencere büyüdükçe sorgu maliyeti artar.
Bu yaklaşım transaction snapshot değildir; tarama sırasında değişen veriler
sonraki poll'da yakınsar. Çok büyük listeler için server sync/Realtime ayrı
ölçekleme işidir; bu sürüm push bildirim veya Realtime aboneliği içermez.

Arka plana geçiş bekleyen yanıtları generation ile geçersiz kılar, eşleşme
listesini temizler. Profil düzenleme formuna otomatik tam reload uygulanmaz.
Hesap değişimi veya yenileme hatası eski eşleşmeleri gizler. Ağ düzelince
poll yeniden dener. Widget dispose zamanlayıcıyı kapatır. RPC'lerin kendi
RLS/hesap/engel kontrolleri yetkili kaynak olmaya devam eder.

Bu PR ayrıca PR #15'in feature/round-results dalına birleşmiş geçmişini main'e
taşır; PR #14 daha önce main'e alınmıştı. Yeni Supabase migration yoktur.
Fiziksel cihazda ağ/lifecycle ve uzun liste performansı kabulü hâlâ gereklidir.
