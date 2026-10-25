import 'package:supabase_flutter/supabase_flutter.dart';

class Person {
  const Person({required this.id, required this.name, this.visible = true});
  final String id;
  final String name;
  final bool visible;
  factory Person.fromJson(Map<String, dynamic> data) => Person(
    id: data['id'] as String,
    name: data['display_name'] as String,
    visible: data['discoverable'] as bool? ?? true,
  );
}

class OwnProfile {
  const OwnProfile(this.person, this.birthDate, this.city, this.interests);
  final Person person;
  final DateTime birthDate;
  final String city;
  final String interests;
}

class Connection {
  const Connection(this.id, this.otherId, this.name);
  final String id;
  final String otherId;
  final String name;
}

class FeedCursor {
  const FeedCursor(this.createdAt, this.id);
  // Keep PostgreSQL microseconds intact; do not round through a local date.
  final String createdAt;
  final String id;
  Map<String, dynamic> toParams() => {'p_before_time': createdAt, 'p_before_id': id};
}

class FeedPage<T> {
  const FeedPage(this.items, this.next);
  final List<T> items;
  final FeedCursor? next;
}

FeedPage<T> decodeFeedPage<T>(List rows, T Function(Map<String, dynamic>) decode) {
  final visible = rows.take(20).map((row) => Map<String, dynamic>.from(row as Map)).toList();
  final last = visible.isEmpty ? null : visible.last;
  return FeedPage(visible.map(decode).toList(), rows.length > 20 && last != null
    ? FeedCursor(last['created_at'] as String, last['id'] as String) : null);
}

class Backend {
  Backend(this.client);
  final SupabaseClient client;
  String get userId => client.auth.currentUser!.id;

  Future<OwnProfile?> profile() async {
    final user = userId;
    final p =
        await client.from('profiles').select().eq('id', user).maybeSingle();
    if (p == null) return null;
    final d =
        await client
            .from('profile_details')
            .select()
            .eq('user_id', user)
            .single();
    return OwnProfile(
      Person.fromJson(p),
      DateTime.parse(d['birth_date'] as String),
      d['city'] as String,
      d['interests'] as String,
    );
  }

  Future<void> saveProfile({
    required String name,
    required DateTime birthDate,
    required String city,
    required String interests,
    required bool visible,
  }) async {
    await client.rpc(
      'save_profile',
      params: {
        'p_name': name.trim(),
        'p_birth_date':
            '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
        'p_city': city.trim(),
        'p_interests': interests.trim(),
        'p_discoverable': visible,
      },
    );
  }

  Future<FeedPage<Person>> discover({FeedCursor? before}) async {
    final rows = await client.rpc('discover_page', params: before?.toParams() ?? {});
    return decodeFeedPage<Person>(rows as List, Person.fromJson);
  }

  Future<bool> like(String id) async =>
      await client.rpc('like_profile', params: {'p_target': id}) != null;

  Future<FeedPage<Connection>> matches({FeedCursor? before}) async {
    final rows = await client.rpc('matches_page', params: before?.toParams() ?? {});
    return decodeFeedPage<Connection>(rows as List, (r) => Connection(
      r['id'] as String, r['other_id'] as String, r['display_name'] as String,
    ));
  }

  Future<void> block(String id) async {
    await client.rpc('block_profile', params: {'p_target': id});
  }

  Future<List<Person>> blockedProfiles() async {
    final rows = await client.rpc('blocked_profiles');
    return (rows as List)
        .map((r) => Person.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> unblock(String id) async {
    await client.rpc('unblock_profile', params: {'p_target': id});
  }

  Future<void> deleteAccount(String password) async {
    final response = await client.functions.invoke(
      'delete-account',
      body: {'password': password, 'confirmation': 'DELETE'},
    );
    if (response.status != 200 ||
        response.data is! Map ||
        response.data['deleted'] != true) {
      throw StateError('Account deletion was not confirmed');
    }
  }

  Future<void> report(String id, String reason) async {
    await client.rpc(
      'report_profile',
      params: {'p_target': id, 'p_reason': reason.trim()},
    );
  }
}

bool isAdult(DateTime birth, DateTime today) {
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day))
    age--;
  return age >= 18 && birth.year >= 1900;
}

String friendlyError(Object error) {
  if (error is FunctionException) {
    final details = error.details;
    final code = details is Map ? details['error'] : null;
    if (code == 'PASSWORD_INVALID') return 'Şifren doğru değil. Tekrar dene.';
    if (code == 'AUTH_REQUIRED') return 'Oturumun geçersiz. Tekrar giriş yap.';
    return 'Hesap silinemedi. Bir süre sonra tekrar dene; gerekirse yeniden giriş yap.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'E-posta veya şifre hatalı.';
      case 'email_not_confirmed':
        return 'Önce e-posta adresini doğrula.';
      case 'over_email_send_rate_limit':
        return 'E-posta gönderim sınırına ulaşıldı. Bir süre sonra tekrar dene.';
      case 'email_address_not_authorized':
        return 'Test e-posta servisi bu adrese gönderim yapamıyor. Yönetici SMTP ayarını tamamlamalı.';
      case 'user_already_exists':
        return 'Bu hesap zaten mevcut. Giriş yapmayı dene.';
      default:
        return 'Giriş işlemi tamamlanamadı. Bilgilerini ve bağlantını kontrol et.';
    }
  }
  if (error is PostgrestException) {
    if (error.code == 'PGRST205' ||
        error.code == 'PGRST202' ||
        error.code == '42P01') {
      return 'Veritabanı kurulumu henüz tamamlanmadı. Supabase migration dosyası uygulanmalı.';
    }
    switch (error.message) {
      case 'AUTH_REQUIRED':
        return 'Oturumunu ve e-posta doğrulamanı kontrol et; tekrar giriş yap.';
      case 'ADULTS_ONLY':
        return 'PlayMatch yalnızca 18 yaş ve üzeri kullanıcılar içindir.';
      case 'BIRTH_DATE_IMMUTABLE':
        return 'Doğum tarihi kayıt sonrasında değiştirilemez.';
      case 'PROFILE_UNAVAILABLE':
        return 'Bu profil şu anda erişilebilir değil. Listeyi yenile.';
      case 'LIKE_LIMIT':
        return 'Günlük 100 beğeni sınırına ulaştın.';
      case 'REPORT_LIMIT':
        return 'Günlük şikâyet sınırına ulaştın.';
      default:
        return 'İşlem kaydedilemedi. Alanları kontrol edip tekrar dene.';
    }
  }
  return 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.';
}
