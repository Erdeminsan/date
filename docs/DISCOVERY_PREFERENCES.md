# Keşfet yaş tercihi

Geliştirme ortamında 20261026030804_discovery_preferences migration’ı uygulandı.
Flutter keşfet sekmesindeki ayar simgesi yaş aralığı ekranını açar. Kayıt
başarılı olunca keşfet baştan yüklenir; önceki keyset cursor kullanılmaz.
Kayıt hatası seçimi korur. İlk okuma başarısızsa varsayılan değerlerle kayıt
butonu gösterilmez; kullanıcı eski tercihini yanlışlıkla ezemez.

Tercih private tabloda kullanıcı başına saklanır, profil silinince cascade
silinir. Ham tablo istemcilere kapalıdır. Okuma/yazma RPC’leri aktörü JWT’den
alır. Minimum 18..100, maksimum minimum..99 veya null (üst sınır yok).
Arayüzün 100+ üst seçimi null’a dönüşür; ilk kullanım 18/null, tüm yetişkinler.
Yaş sınırları dahildir, PostgreSQL age(current_date,birth_date) ile sunucunun
takvim gününde hesaplanır. Yaş filtresi doğum tarihi olmayan eksik profilleri
keşfetten çıkarır. Karşı tarafın tercihini değiştirmez, karşılıklı filtre,
cinsiyet/mesafe/şehir tercihi veya mevcut eşleşmeyi kaldırma yapmaz.

Filtre discover_page ve eski discover_profiles RPC’sinde LIMIT’ten önce
uygulanır. Public fonksiyonlar invoker kalır; mevcut RLS, engel/yasak/görünürlük
ve beğeni hariç tutma kuralları korunur. Private helper yalnız kaydedilmiş
tercihe uygunluk döndürür; doğum tarihini/şehir/ilgi alanlarını döndürmez.
Yaş aralığına uygun bir profilin listelenmesi yaklaşık yaş hakkında bilgi
verir; filtre tam doğum tarihinin gizliliği için mutlak çıkarım engeli değildir.
Profil açıklaması yaşın bu amaçla kullanıldığını belirtir. Kilitli şehir ve
ilgi alanlarına göre filtre eklenmedi.

Testler tam yaş sınırı, kullanıcı izolasyonu, geçersiz aralık, anon erişimi,
filtrelenmiş 20’lik sayfalar ve tam profil test verileriyle çalışır. Veritabanı
planı büyük veri üzerinde ölçülmedi; satır başına uygunluk fonksiyonunun
maliyeti yük testinde değerlendirilmelidir. Gerçek cihaz slider/ekran kabulü
ve ürünün diğer keşfet tercihleri için kapsam kararı hâlâ açık.
