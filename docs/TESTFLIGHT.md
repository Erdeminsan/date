# PlayMatch kapalı TestFlight betası

Durum: yayın hazırlığı. Henüz imzalı IPA üretilmedi veya Apple'a yüklenmedi.
Bu sürüm kayıt/profil/beğeni/eşleşme, şikâyet/engel/hesap silme ve tek kişilik
Sky Hop antrenmanını kapsar. Çok oyunculu oyun, sohbet ve profil kilidi açma yoktur.

## Araçlar

Apple 28 Nisan 2026'dan beri yüklemelerde Xcode 26 / iOS 26 SDK veya üstünü
istiyor. CI Flutter 3.38.0'a sabitlenmiştir (bu sürüm Xcode 26'yı destekler).
Eski Flutter 3.29 ile yayın derlemesi yapmayın. Yerel ve CI SDK'sını eşleştirin.
Xcode'un istediği macOS sürümünü Mac'inizde kurmanız gerekebilir.

```bash
flutter --version
xcodebuild -version
sw_vers
bash scripts/setup.sh
python3 scripts/testflight_preflight.py
```

`setup.sh` eksik iOS/Android projelerini oluşturur; var olan imzalama dosyalarını
silmez. Ürün adı PlayMatch, önerilen bundle ID `com.erdeminsan.playmatch`.
Bu bundle ID'nin Developer hesabında kullanılabilirliği henüz doğrulanmadı.

## Auth: yayın öncesi zorunlu gerçek test

Supabase Dashboard > Authentication > URL Configuration > Redirect URLs:

```
com.erdeminsan.playmatch://auth-callback
```

Bu adresi tam eşleşmeyle ekleyin. Native scheme setup scripti tarafından yazılır.
Flutter'ın varsayılan deep link işleyicisi kapatılır; bağlantıyı Supabase SDK alır.
Site URL ve Custom SMTP kendi kontrolünüzde doğru yapılandırılmalıdır. Email
confirmation açık kalır. Bu dashboard ayarları kod eklenmesiyle otomatik değişmez.
Recovery e-postası şablonu `{{ .ConfirmationURL }}` kullanmalıdır.

1. Fiziksel iPhone'da kayıt olun; e-postayı aynı cihazda açın. Uygulamaya dönüşü
   hem uygulama açıkken hem tamamen kapalıyken deneyin.
2. Giriş ekranında Şifremi unuttum: e-postayı açınca Yeni şifre ekranı gelmeli.
   Yeni şifreyle giriş başarılı, eski şifre başarısız olmalı. Süresi dolmuş/kullanılmış
   link hesap değiştirmemeli; yeni sıfırlama talebi denenmeli.
3. İki gerçek test hesabıyla karşılıklı beğeni/eşleşme, engel, engel kaldırma,
   şikâyet ve yalnızca test hesabı üzerinde hesap silme akışını deneyin.
4. Uçak modu, uygulamayı kapatıp açma ve küçük iPhone ekranını deneyin.

## Apple imzalama ve yükleme

1. `open ios/Runner.xcworkspace` ile Xcode'u açın. Runner > Signing & Capabilities:
   aktif Developer Team'inizi seçin, Automatically manage signing'i açın.
   Bundle ID'yi Apple kaydı ile aynı yapın. Team ID/sertifika özel anahtarlarını
   sohbete veya repoya göndermeyin.
2. Gerçek bir uygulama ikonu yerleştirin: Runner/Assets.xcassets/AppIcon.appiconset.
   Scaffold'un Flutter varsayılan ikonuyla dış test yayını yapmayın.
3. App Store Connect'te aynı bundle ID ile iOS uygulama kaydı oluşturun. Apple
   sözleşmeleri, yaş derecelendirmesi ve gerekli iletişim alanlarını tamamlayın.
4. İlk başarılı `flutter pub get` sonrası `pubspec.lock` dosyasını repoya ekleyin.
   CI artifact'ı da lockfile sağlar; release çözümünü aynı SDK ile doğrulayın.
5. Daha önce yüklenmemiş artan build numarası seçin:

   ```bash
   bash scripts/build_testflight.sh 3
   ```

6. Xcode Organizer'da arşivi Validate App ile doğrulayın. Privacy Report'u
   inceleyin: kullanılan SDK'ların privacy manifestleri ve required-reason API
   bildirimleri arşivde bulunmalı. Şifreleme beyanını gerçek uygulamaya göre
   tamamlayın; script otomatik muafiyet beyanı yazmaz.
7. Distribute App > App Store Connect ile yükleyin. İşlenmesini bekleyip önce
   yalnızca yetkili dahili test grubuna ekleyin. İmzasız CI derlemesi TestFlight'a
   yüklenebilir bir IPA değildir.
8. Dış test için beta açıklaması, test talimatları, geri bildirim e-postası,
   review iletişim bilgileri ve gerekiyorsa çalışan review hesabını sağlayın.
   İlk dış beta Apple incelemesine tabidir; kabul garantisi yoktur.

## Yayını engelleyen doğrulamalar

- [ ] Flutter analiz/widget testleri ve iOS release derlemesi başarılı.
- [ ] `pubspec.lock` commit edildi; fiziksel iPhone'da auth kabul testleri geçti.
- [ ] SMTP, Site URL ve redirect allowlist gerçek ortamda doğrulandı.
- [ ] Uygulama ikonu hazır; Apple Team/bundle ID eşleşmesi ve imzalama geçti.
- [ ] Veri sorumlusu/iletişim adresi belli; gerçek gizlilik ve destek URL'leri hazır.
- [ ] App Privacy cevapları: e-posta, kullanıcı ID, ad, doğum tarihi, şehir,
      ilgi alanları, beğeniler/eşleşmeler ve şikâyet kayıtlarının gerçek kullanımına
      göre incelendi. “Veri toplamıyor” denmemeli.
- [ ] Dış test öncesi kullanım koşulları, kullanıcı içeriği kuralları ve şikâyet
      inceleme sorumlusu/iş akışı hazır. Mevcut report tablosu tek başına moderasyon değildir.
- [ ] Arşiv doğrulandı, yüklendi ve TestFlight'tan gerçek cihaza kurulabildi.

Resmi kaynaklar:
- https://developer.apple.com/news/upcoming-requirements/
- https://docs.flutter.dev/deployment/ios
- https://docs.flutter.dev/release/whats-new
- https://supabase.com/docs/reference/dart/auth-resetpasswordforemail
