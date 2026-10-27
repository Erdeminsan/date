# Edge istek gövdesi sınırları

finish-round: 2048 bayt; delete-account: 4096 bayt; report-photo: 8192 bayt.
Ortak request-body.mjs okuyucusu JSON'u tüm gövdeyi sınırsız tamponlamadan okur.
Content-Length başlığına güvenmez; UTF-8 baytlarını sayar. Sınır aşımında stream
iptal edilir ve 413 BODY_TOO_LARGE döner. Beş saniyelik toplam gövde okuma
süresi aşılırsa 408 REQUEST_TIMEOUT döner. Bozuk UTF-8/JSON veya stream hatası
400 INVALID_REQUEST döndürür; ham hata metni dışarı çıkmaz.

Bu retler Auth istemcisi, şifre kontrolü, rapor veya sonuç RPC çağrısından önce
gerçekleşir. Mevcut kimlik/katılımcı ve yetki denetimleri korunur. Boyut sınırı
istek hızı sınırı değildir; genel IP/hesap hız sınırlaması ayrıca açıktır.
Platformun gelen tek bir chunk'ı tamponlamasını uygulama kontrol edemez;
okuyucu kendi biriktirdiği gövdeyi sınırlar.

Testler: parçalanmış çok baytlı UTF-8, tam sınır, yanıltıcı Content-Length,
tamamlanmayan büyük yükleme, okuma süresi, bozuk/boş gövde, stream hatası ve
üç handler için byte-heavy JSON'un yan etki oluşturmadan reddedilmesi.
