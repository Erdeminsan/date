# Fiziksel cihaz kabulü

Bu liste hazırlanmıştır; henüz hiçbir satır fiziksel cihazda geçti sayılmamıştır.
Yalnız test hesapları kullanın. Hesap silme/engelleme/moderasyon kontrollerini
gerçek kullanıcılar üzerinde yapmayın. Şifre, token ve özel kullanıcı içeriği
hata kayıtlarına eklenmemeli.

## Başlangıç kaydı

- Test tarihi:
- main commit SHA:
- Uygulama sürümü/build:
- iPhone A modeli/iOS:
- Cihaz B modeli/iOS (gerçek ikinci cihaz):
- Ortam: geliştirme Supabase / test hesapları
- Moderasyon test hesabı ve yetkisi doğrulandı mı:
- Test sonucu ve hata numaraları:

## Kurulum

1. main dalını güncelleyin; kendi değişiklikleriniz varsa önce git status ile kontrol edin.
2. TESTFLIGHT.md araç/kurulum ve imzalama adımlarını uygulayın.
3. İki ayrı doğrulanmış test hesabı ve gerektiğinde ayrı moderatör hesabı kullanın.
4. SMTP, Site URL ve auth callback izin listesini kontrol edin.
5. Test süresince cron/Edge hata kayıtları ve iş kuyruğunu izleyin.
   Sonuç işçisini test etmek için iki oyuncunun tüm girdilerinin sunucuya
   ulaştığı doğrulandıktan sonra uygulamaları kapatın.

## Kabul matrisi

Her satır için Geçti/Kaldı, cihaz ve hata kaydı ekleyin. Boş satır test edilmemiştir.

| Senaryo | Beklenen | Sonuç / hata |
| --- | --- | --- |
| Kayıt ve doğrulama, uygulama açık/kapalı | Doğru hesaba dönüş; onaysız hesap erişemez | |
| Şifre sıfırlama, kullanılmış/süresi dolmuş link | Yeni şifre çalışır; hatalı link hesap değiştirmez | |
| Profil, 18+ ve görünürlük | Sunucu doğrulaması; gizli alanlar başkasına açılmaz | |
| Galeriden fotoğraf, değiştir/sil | Doğru fotoğraf; eski dosya/önbellek geri gelmez | |
| Yaş tercihi ve keşfet sayfalama | Tercihe uygun, tekrarsız kayıtlar | |
| Karşılıklı beğeni/eşleşme | Tek eşleşme; diğer cihaz kendiliğinden güncellenir | |
| Sohbet, geçmiş, bağlantı hatası sonrası retry | Kalıcı ve tek mesaj; doğru sıralama | |
| Davet kabul/ret/iptal ve süre aşımı | İki cihaz aynı oda durumunu görür | |
| Ortak başlangıç ve 45 saniyelik tur | Aynı engeller; doğru başlangıç ve süre | |
| Galibiyet 1/2, kayıp ve beraberlik | Yalnız kazanan şehir → ilgi açar; beraberlik yeni alan açmaz | |
| İki cihaz tam girdi sonrası kapanır | Cron/işçi tek sonuç üretir; açınca sonuç görülebilir | |
| Eksik girdi/uzun kopuş/erken arka plan | Yarım tur ödül üretmez | |
| Wi-Fi/mobil veri geçişi ve kısa kesinti | Sınırlı retry; değiştirilmiş/geç paket kabul edilmez | |
| Aynı sonuç tekrar istenir | İkinci ödül veya sonuç oluşmaz | |
| Sohbet/oyun/sonuç açıkken engel veya unmatch | Yetki kaldırılır; eski içerik geri gelmez | |
| Profil/mesaj/fotoğraf şikâyeti | Gerekçe ve doğru kanıt; ortak kota korunur | |
| Moderatör inceleme, kısıtlama ve itiraz | Yetkisiz/kendi vakasına erişim yok; doğru kullanıcı açıklaması | |
| Uygulama arka planı ve rol/hesap erişimi kaybı | Hassas içerik temizlenir; eski yanıt geri koymaz | |
| Test hesabını silme ve eski oturum | Hesap/fotoğraf/ilişkiler temizlenir; eski oturum erişemez | |
| Küçük ekran, büyük metin, klavye | İşlem düğmeleri erişilebilir; taşma yok | |
| İmzalı build kurulumu ve yeniden açma | Doğru sürüm/ortam; başlangıç hatası yok | |

Cihaz kabulü geçmesi tek başına yayın izni değildir. Gizlilik/destek/koşullar,
operatör sorumluluğu, saklama politikası ve App Store Connect bilgileri ayrıca
tamamlanmalı; TestFlight kurulumu gerçekten denenmeden tamamlandı işaretlenmemeli.
