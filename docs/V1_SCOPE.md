# PlayMatch 1.0.0 kabul kapsamı

1.0.0 etiketi, yalnızca aşağıdaki temel kullanıcı akışlarının tamamı uçtan uca
çalıştığında verilecek. Mevcut sürüm 0.3.0+3 kalır. Teknik derleme başarısı,
ürünün tamamlandığı veya TestFlight'a yüklendiği anlamına gelmez.

## Tamamlanma ölçütleri

| Alan | 1.0.0 kabulü | Mevcut durum |
| --- | --- | --- |
| Üyelik | Kayıt, doğrulama, giriş/çıkış, sıfırlama, hesap silme; gerçek cihazda soğuk/sıcak başlangıç | Kod var; gerçek e-posta/cihaz kabulü eksik |
| Profil | 18+ profil, düzenleme, fotoğraf, görünürlük ve keşfet tercihleri | Metin profili ve özel fotoğraf akışı main içinde; gerçek cihaz kabulü ve tercihler eksik |
| Keşfet | Tercihlere uygun, engelli/yasaklı hesapları dışlayan, devamı yüklenebilen liste | 20 kayıtlık sayfalama var; tercihler eksik |
| Eşleşme | Karşılıklı beğeni, limit, eşleşmeden ayrılma, sayfalama ve otomatik güncelleme | Karşılıklı beğeni ve sayfalama var; ayrılma geliştirme dalında; otomatik güncelleme eksik |
| Ortak oyun | Davet, kabul/ret/iptal, oda, ortak başlangıç, bağlantı kopması ve zaman aşımı | Dart/JS motor ve antrenman main içinde; davet/bekleme odası geliştirme dalında, ortak tur yok |
| Sonuç ve bilgi açılması | Sunucunun doğruladığı sonuç; aynı sonucu tekrar göndermek güvenli; yalnızca ilgili eşleşmeye erişim | Offline replay motoru var; canlı sonuç kabulü ve bilgi açılması yok |
| Mesajlaşma | Yalnızca izinli eşleşmeler; kalıcı mesajlar, sayfalama, otomatik güncelleme, gönderim hatası/tekrar; engel/yasak kontrolü | Metin sohbeti geliştirme dalında; 3 sn polling, güvenli retry ve erişim kontrolleri var; gerçek cihaz kabulü eksik |
| Güvenlik/moderasyon | Şikâyet inceleme ve yaptırım, denetim kaydı, silme/saklama politikası, kötüye kullanım sınırları | Engelle/şikâyet kaydı var; yönetim akışı eksik |
| Kullanıcı bilgilendirmesi | Gerçek destek ve gizlilik bağlantıları, kullanım koşulları, veri kullanımı ve hesap silme açıklaması | İşletmeci bilgileri/metinler eksik |
| Yayın | Otomatik testler, iki gerçek hesap, fiziksel iPhone, ağ kopması, imzalı arşiv ve TestFlight kurulumu | CI geçti; cihaz/imza/kabul eksik |

Oyunla açılacak bilgiler şehir ve ilgi alanlarıdır; doğum tarihi özel kalır.
Onaylanan kural: yalnız kazananın ilk galibiyetinde rakibinin şehri, ikinci
galibiyetinde ilgi alanları açılır. Eşitlikte bilgi açılmaz. Mesajlaşma eşleşme oluşunca iki tarafa da açılır;
oyun ön koşulu yoktur.

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

Oyun tasarımı, onaylanan ödül kuralı ve açık kararlar: [GAME_PLAN.md](GAME_PLAN.md).

## 25 Ekim 2026 main değerlendirmesi

PR #8 ile fotoğraf, ortak fizik motoru ve antrenman entegrasyonu ana dala geldi.
Tüm uzak özellik/düzeltme dallarının geçmişi main altında toplandı. Eski dal
isimlerinin kalması kodun dışarıda olduğu anlamına gelmez; dallar silinmedi.
Sürüm hâlâ 0.3.0+3; 1.0.0 veya TestFlight dağıtımı yapılmış değildir.

Son kod doğrulaması: PR #8, 6ecdf2e, Actions 40218069199. Flutter analizi,
43 Flutter + 19 JS motor + 25 DB + 15 Edge + 2 platform testi (104 toplam)
ve Xcode 26 imzasız iOS release derlemesi başarılı. Bu durum değerlendirmesi
ve geçmiş birleştirmesi çalışma kodunu değiştirmiyor.

### Kalan işlerin önceliği

1. Ortak oyun: davet/kabul/ret/iptal, katılımcı yetkileri, tek aktif oda,
   hazır olma, sunucu başlangıç saati, süre aşımı ve kopuş yönetimi.
2. Canlı skor doğrulama: sıralı giriş paketleri, zaman pencereleri,
   sürüm kontrolü, sunucu replay ve tek seferlik sonuç kaydı.
3. Kazanan ödülü: ilk galibiyette şehir, ikinci galibiyette ilgi alanları;
   eşitlik/yarım tur ödülsüz; erişim yalnızca ilgili eşleşmeye ait.
4. Ürün akışları: keşfet tercihleri, eşleşmeden ayrılma, otomatik güncellemeler,
   kalıcı mesajlaşma. Demo sohbeti yalnızca bellekte; gerçek mesajlaşma değildir.
   Onaylanan sohbet kuralı: eşleşme oluşunca iki taraf da yazışabilir.
5. Moderasyon: şikâyet inceleme, yaptırım, denetim kayıtları, fotoğraf içerik
   kontrolü ve saklama/silme süreçleri.
6. Yayın kabulü: gerçek e-posta/SMTP ve yönlendirmeler, iki hesaplı fiziksel
   iPhone testleri, canlı fotoğraf ve hesap silme, gizlilik/destek/işletmeci
   metinleri, imzalı arşiv ve TestFlight kurulumu. Android galeri süreç kaybı
   kurtarması ayrıca açık; iOS derleme başarısı Android kabulü değildir.

Sıradaki geliştirme paketi 1. maddedir. Fotoğraf/kimlik işlemlerinin gerçek
cihaz kabulü, yeni geliştirmeler sürerken ayrıca yürütülebilir.

Davet paketi ve sınırları: [GAME_INVITATIONS.md](GAME_INVITATIONS.md).

## Eşleşmeden ayrılma paketi

Eşleşme kartındaki menüden onayla ayrılma ekleniyor. İki yöndeki beğeni ve
ilgili oyun odaları kaldırılır; kota olayları korunur. Bu işlem engelleme
oluşturmaz: profiller yeniden keşfedilebilir, yeni eşleşme için iki tarafın
da yeniden beğenmesi gerekir. Eski eşleşme ID’sine tekrar istek yeni eşleşmeyi
silemez. Erişilemeyen veya bulunmayan eşleşme aynı başarılı no-op yanıtını verir.

İşlem beğeni/engel/davet ile aynı çift kilidini kullanır. Gelecekteki mesaj ve
bilgi erişimi tabloları da match FK üzerinden silinmeli veya aktif eşleşmeyi
kontrol etmelidir. Şu an bu tablolar henüz yoktur.

Kalıcı sohbet paketi: [MESSAGING.md](MESSAGING.md).
