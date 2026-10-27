# Şikâyet kotası

Profil, seçili mesaj ve fotoğraf şikâyetleri aynı kullanıcı başına son 24 saatte
10 başarılı rapor sınırını paylaşır. Sayaç app_private.report_events içindedir:
rastgele olay kimliği, şikâyetçi hesap kimliği ve zaman. Hedef kimliği, rapor
metni, fotoğraf veya mesaj içeriği tutulmaz. İstemcinin tabloya veya kayıt
trigger fonksiyonuna erişimi yoktur; RLS deny-all uygulanır.

Üç yazma yolu mevcut kullanıcı advisory transaction kilidini (seed 3) kullanır.
Kontrol olay tablosundan yapılır. Fotoğraf hazırlığında kontrol edilen kota
finalization içinde yeniden denetlenir. AFTER INSERT trigger raporla aynı
transaction içinde bir olay ekler; başarısız işlem/rollback bütçe harcamaz.
Mesaj/fotoğrafın idempotent tekrarları rapor INSERT etmediğinden ek olay üretmez.
Genel profil şikâyeti mevcut davranışı korur: her başarılı çağrı ayrı rapordur;
bu yol için istek UUID'siyle belirsiz yanıt tekrarını tekilleştirme ayrıca açıktır.

Hedef hesap veya rapor silinmesi sayacı azaltmaz. Şikâyetçinin hesabı silinirse
olayları cascade temizlenir. Başarılı yeni raporda aynı kişinin 24 saatten eski
olayları temizlenir; aktif olmayan hesaplar için zamanlanmış global temizlik yoktur.
Süresi geçen olaylar kota hesabına katılmaz.

Migration, rapor yazmalarını kilitleyerek mevcut son 24 saatlik raporları aktarır.
Daha önce silinen raporların geçmişi geri üretilemez; tam muhasebe dağıtımdan
itibaren oluşur. Mevcut RPC imzaları ve hata kodu REPORT_LIMIT değişmez.

Testler: migration backfill, profil/mesaj/fotoğraf ortak sınırı, rapor/hedef
silinmesine dayanıklılık, başarısız yazma ve transaction rollback, sürenin dolması,
idempotent tekrar, istemci erişim reddi ve şikâyetçi hesap silme.
PGlite testleri tek bağlantılıdır; gerçek çok bağlantılı yarış kabulü ayrıca açıktır.
