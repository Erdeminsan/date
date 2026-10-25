# Kalıcı mesajlaşma

Eşleşme kartı sohbeti açar. Oyun davetine sohbet başlığından veya eşleşme
menüsünden ulaşılır. Mesajlaşma için oyun kazanmak/tamamlamak gerekmez.
Metin mesajı 1–1000 karakterdir; dosya, fotoğraf, ses, okundu veya yazıyor
bildirimleri bu pakette yoktur. Metin düz Text bileşeniyle çizilir.

## Yetki ve gönderim

Mesajların match FK’si ON DELETE CASCADE kullanır. Eşleşmeden ayrılma,
engelleme ve hesap silme ilgili geçmişi siler. Yasaklı veya silinmekte olan
hesaplar için okuma/gönderim kapalıdır. Gizli profil daha önceki eşleşmede
sohbet edebilir. Yeni tabloya istemci doğrudan yazamaz/değiştiremez; public
invoker RPC özel definer işlemini çağırır. Gönderen sunucudaki auth.uid’den
alınır. Çift kilidi ayrılma, engelleme ve davet işlemleriyle ortaktır.

Her taslak kriptografik rastgele UUID alır. Aynı kullanıcı/istek kimliği ve
aynı içerik tekrar gönderilirse aynı kayıt döner; içerik veya eşleşme değiştirilirse
reddedilir. Ağ hatasında taslak sabit kalır ve tekrar deneme aynı kimliği kullanır.
Bu kimlik ekran belleğindedir; uygulama kapanınca gönderilmemiş taslak saklanmaz.
Gönderim sonrası okuma gecikebilir; sunucuda kayıtlı mesaj polling ile görünür.
Dakikada en fazla 60 yeni mesaj vardır. Özel kota olayları eşleşme silinince
silinmez; hesap silinince silinir. Retry tekrar kota harcamaz.

## Geçmiş ve yenileme

İlk sayfa son 50 mesajdır; önceki mesajlar kimlik imleciyle yüklenir. Yeni
mesajlar son görülen kimlikten ileri, artan sırada 50’lik sayfalarla alınır.
Böylece bağlantı kesintisinde 50’den fazla mesaj birikmesi aradaki mesajları
atlamaz. Kimlik RPC JSON’unda metindir; istemci BigInt ile sıralar.

Ekran açıkken 3 saniyelik polling vardır; push veya Realtime değildir.
Arka planda durur; dönüşte yenilenir. Okuma hatası geçmişi ekrandan temizler ve
gönderimi kapatır; yenileme ile tekrar denenir. Daha önce görülmüş/ekran görüntüsü
alınmış içerik geri alınamaz. Hesap değişince eski taslağın gönderilmesi engellenir.

## Doğrulama ve kalanlar

Yerel DB testleri üçüncü kullanıcı, yasaklı katılımcı, doğrudan yazma yasağı,
tekrar gönderim/çelişen içerik, kota, 50’den büyük eski/yeni sayfalar ve ayrılma
sonrası temizliği kapsar. UI testleri kayıp yanıtla retry, eski içerik temizliği,
hesap değişimi ve lifecycle timer temizliğini kapsar. Gerçek iki cihaz/ağ kabulü,
bildirimler ve mesaj bazlı moderasyon araçları henüz tamamlanmadı.

Migration `20261025182711` geliştirme projesine uygulandı. Canlı kontrollerde
anon gönderim kapalı, doğrudan INSERT kapalı, üye okuma RPC’si açık ve RLS açık.
