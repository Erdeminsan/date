# PlayMatch 1.0.0 kabul kapsamı

1.0.0 etiketi, yalnızca aşağıdaki temel kullanıcı akışlarının tamamı uçtan uca
çalıştığında verilecek. Mevcut sürüm 0.3.0+3 kalır. Teknik derleme başarısı,
ürünün tamamlandığı veya TestFlight'a yüklendiği anlamına gelmez.

## Tamamlanma ölçütleri

| Alan | 1.0.0 kabulü | Mevcut durum |
| --- | --- | --- |
| Üyelik | Kayıt, doğrulama, giriş/çıkış, sıfırlama, hesap silme; gerçek cihazda soğuk/sıcak başlangıç | Kod var; gerçek e-posta/cihaz kabulü eksik |
| Profil | 18+ profil, düzenleme, fotoğraf, görünürlük ve keşfet tercihleri | Metin profili var; fotoğraf/tercihler eksik |
| Keşfet | Tercihlere uygun, engelli/yasaklı hesapları dışlayan, devamı yüklenebilen liste | Temel liste var; tercihler/sayfalama eksik |
| Eşleşme | Karşılıklı beğeni, limit, eşleşmeden ayrılma, sayfalama ve otomatik güncelleme | Karşılıklı beğeni var; kalan akışlar eksik |
| Ortak oyun | Davet, kabul/ret/iptal, oda, ortak başlangıç, bağlantı kopması ve zaman aşımı | Yok; mevcut oyun tek kişilik antrenman |
| Sonuç ve bilgi açılması | Sunucunun doğruladığı sonuç; aynı sonucu tekrar göndermek güvenli; yalnızca ilgili eşleşmeye erişim | Yok |
| Mesajlaşma | Yalnızca izinli eşleşmeler; kalıcı mesajlar, sayfalama, otomatik güncelleme, gönderim hatası/tekrar; engel/yasak kontrolü | Yok |
| Güvenlik/moderasyon | Şikâyet inceleme ve yaptırım, denetim kaydı, silme/saklama politikası, kötüye kullanım sınırları | Engelle/şikâyet kaydı var; yönetim akışı eksik |
| Kullanıcı bilgilendirmesi | Gerçek destek ve gizlilik bağlantıları, kullanım koşulları, veri kullanımı ve hesap silme açıklaması | İşletmeci bilgileri/metinler eksik |
| Yayın | Otomatik testler, iki gerçek hesap, fiziksel iPhone, ağ kopması, imzalı arşiv ve TestFlight kurulumu | CI geçti; cihaz/imza/kabul eksik |

Oyunla açılacak bilgiler şehir ve ilgi alanlarıdır; doğum tarihi özel kalır.
Bilgi açılmasının oyun kuralı ve mesajlaşmanın açılma koşulu uygulamaya geçmeden
önce kesinleştirilecek. Kullanıcıdan onay alınmış bir kazanma/puan kuralı henüz yok.

## Uygulama sırası

1. Doğrulanmış güvenlik hataları, hesap akışı ve regresyon testleri.
2. Keşfet/eşleşme sayfalaması, toplu veri sorguları, profil fotoğrafı ve tercihler.
3. Davet/oda yaşam döngüsü, ortak oyun, sunucuda sonuç doğrulama ve bilgi erişimi.
4. Mesajlaşma ve otomatik güncellemeler; engelleme ve yaptırımların tüm yeni yüzeylere uygulanması.
5. Moderasyon yönetimi, bilgilendirme ekranları, gerçek cihaz ve yayın kabulü.

Her aşama ayrı PR ve kabul testleriyle ilerler. Yeni tablolar/RPC'ler için
katılımcı olmayan kullanıcı, engellenen kullanıcı, yasaklı kullanıcı, tekrar
istek ve oturum kaybı senaryoları test edilmeden aşama tamamlanmış sayılmaz.

## İlk düzeltme paketi

- Günlük beğeni sınırı özel bir olay tablosundan hesaplanıyor. Engelleme bu
  sayacı silemez. Aynı beğeninin tekrarı bütçe harcamaz; kaldırılıp tekrar
  oluşturulan beğeni harcar. Limit son 24 saatte 100 işlemdir.
- Sayaç hedef kullanıcı bilgisi tutmaz, istemciler okuyamaz/değiştiremez.
  Yeni bir beğenide çağıranın 24 saatten eski olayları temizlenir; hesap
  silinince tüm sayaç kayıtları silinir.
- Yasaklı/doğrulanmamış/silinmiş hedefler profil, keşfet ve eşleşme erişiminden
  çıkarılır; yeni beğeni kabul edilmez. Geçici yasak bitince eski eşleşme
  tekrar görünür; engelleme ise eşleşmeyi silmeye devam eder.
- Şifre sıfırlamadan vazgeçmek şifreyi değiştirmeden yalnızca mevcut oturumu kapatır.

Geçmişte silinmiş beğeni olayları geri üretilemez. Migration, halen kayıtlı son
24 saatlik beğenileri aktarır; tam günlük muhasebe dağıtımdan itibaren oluşur.
