# Doğrulanmış sonuç ve eşleşmeye özel bilgi erişimi

finish-round Edge servisi, verifyRound çekirdeği ve 20261025192357_round_results
migration'ı geliştirme ortamına uygulandı. Flutter sonuç ekranı geliştirme
dalında. İki fiziksel cihazla uçtan uca kabul henüz yapılmadı.

## Güven sınırı

İstek yalnız room_id taşır. Edge Auth.getUser ile tokenı doğrular; actor ID
ve skorları istemciden almaz. JWT gateway kontrolü kapalıdır çünkü gövde kendi
Auth doğrulamasını yapar. Service anahtarı yalnız Edge ortamındadır.
prepare_game_result ve finalize_game_result yalnız service_role tarafından
çağrılır. Authenticated kullanıcı yalnız kendine ait sonucu game_result ile
okuyabilir; private sonuç tablosuna doğrudan okuma/yazma izni yoktur.

prepare iki katılımcının 90 paketini güvenilir DB alım zamanlarıyla yükler.
Eksik akış pending döner; istemci geçmiş/skor göndererek bunu tamamlayamaz.
Edge replay skorları hesaplar; finalize eşleşme çift kilidi altında hesap,
engel, oda durumu ve süreyi tekrar kontrol eder. İptal veya unmatch araya
girerse sonuç yazılmaz. DB tek bağlantı testleri bu sıralamayı doğrular;
gerçek paralel bağlantı yük testi ayrıca gereklidir.

## Tek sonuç, ayrı ilerleme

room_id sonuç primary key'dir. Skorlar ve completed geçişi aynı transaction'da
yazılır; ikinci finalization mevcut sonucu döndürür. Kazanan DB'de iki replay
skorundan seçilir; beraberlikte winner null. İlerleme ayrı sayaç yerine ilgili
match içindeki tekil kazanan sonuçlarının sayısından türetilir, en fazla iki
alan açılır. Böylece aynı sonucu tekrar göndermek ikinci ödül vermez.

İlk galibiyet rakibin şehrini; ikinci galibiyet ilgi alanlarını açar. İki oyuncu
bağımsız ilerler. Sonraki beraberlik veya yenilgi önceden kazanılmış erişimi
silmez. Doğum tarihi/e-posta payload'a hiç eklenmez. Şehir/ilgi alanları güncel
profilden okunur; profil değişikliği açılmış alana yansır. Unmatch/hesap silme
oda ve sonuçları cascade siler; yeni eşleşme sıfırdan başlar. Engel/yasak
okumayı kapatır. Profil formu ve oyun daveti bu paylaşımı açıklar.

## Kullanıcı akışı ve sınırlar

Son girdi onaylanınca sonuç ekranı açılır. Diğer oyuncu veya tur bitişi
bekleniyorsa iki saniyede bir yeniden denenir; tamamlanınca artık salt okunur
RPC ile erişim kontrolü sürer. Erişim kaybında gösterilen bilgiler temizlenir.
Yanıt kaybı kesin başarısızlık sayılmaz; yeniden deneme aynı sonucu getirir.
Lobide tamamlanmış son turun sonucu tekrar açılabilir. Yeni davet açıldıktan
sonra geçmiş sonuçlar/alanlar için ayrı profil-geçmiş ekranı henüz yoktur.

Sonuç yalnız tur bitişinden sonraki 15 saniyede ilk kez yazılır. İki uygulama
da bu pencere boyunca kapanırsa tam girdiler olsa dahi otomatik arka plan
sonuçlandırıcısı yoktur; tur ödülsüz süre aşımına uğrar. Eksik akış, uzun kopuş
ve iptal galibiyet sayılmaz. Bu davranış cihaz kabulünde doğrulanmalıdır.

Bot tespiti yoktur; replay fiziksel olarak mümkün sonucu doğrular. Genel
Edge HTTP rate limit ve uzun dönem sonuç/girdi saklama politikası henüz ürün
moderasyon/operasyon paketinin açık işleridir.
