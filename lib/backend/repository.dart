import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class Person {
  const Person({required this.id, required this.name, this.visible = true, this.photoPath});
  final String id;
  final String name;
  final bool visible;
  final String? photoPath;
  factory Person.fromJson(Map<String, dynamic> data) => Person(
    id: data['id'] as String,
    name: data['display_name'] as String,
    visible: data['discoverable'] as bool? ?? true,
    photoPath: data['photo_path'] as String?,
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
  const Connection(this.id, this.otherId, this.name, {this.photoPath});
  final String id;
  final String otherId;
  final String? photoPath;
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

class GameRoom {
  GameRoom(Map<String, dynamic> data)
    : id = data['id'] as String, inviterId = data['inviter_id'] as String,
      status = data['status'] as String, expiresAt = DateTime.parse(data['expires_at'] as String),
      inputProtocol = data['input_protocol'] as String?,
      engineVersion = data['engine_version'] as String? ?? 'sky-hop-v1', seed = data['seed'] as int?,
      startsAt = data['starts_at'] == null ? null : DateTime.parse(data['starts_at'] as String);
  final String engineVersion;
  final String? inputProtocol;
  final int? seed;
  final DateTime? startsAt;
  final String id, inviterId, status;
  final DateTime expiresAt;
  bool get active => ['invited','accepted','countdown','running','awaiting_result'].contains(status);
}
class ModerationReport {
  ModerationReport(Map<String,dynamic> data):id=data['id'] as String,reporterName=data['reporter_name'] as String,
    reportedName=data['reported_name'] as String,reason=data['reason'] as String,decision=data['decision'] as String?,note=data['review_note'] as String?;
  final String id,reporterName,reportedName,reason;
  final String? decision,note;
}
class ModerationSanction {
  ModerationSanction(Map<String,dynamic> data):id=data['id'] as String,reportedName=data['reported_name'] as String,
    reason=data['reason'] as String,expiresAt=DateTime.parse(data['expires_at'] as String),
    active=data['active'] as bool,liftReason=data['lift_reason'] as String?;
  final String id,reportedName,reason;
  final DateTime expiresAt;
  final bool active;
  final String? liftReason;
}
class SanctionAppeal {
  SanctionAppeal(Map<String,dynamic> data):id=data['id'] as String,sanctionId=data['sanction_id'] as String,
    appealId=data['appeal_id'] as String?,expiresAt=DateTime.parse(data['expires_at'] as String),
    active=data['active'] as bool,body=data['body'] as String?,decision=data['decision'] as String?,
    response=data['response'] as String?,displayName=data['display_name'] as String?,internalReason=data['internal_reason'] as String?;
  final String id,sanctionId;
  final String? appealId,body,decision,response,displayName,internalReason;
  final DateTime expiresAt;
  final bool active;
}
class DiscoveryPreferences {
  DiscoveryPreferences(Map<String,dynamic> data):minAge=data['min_age'] as int,maxAge=data['max_age'] as int?;
  final int minAge;
  final int? maxAge;
}
class MatchUnlocks {
  MatchUnlocks(Map<String,dynamic> data)
    : level = data['unlock_level'] as int, city = data['city'] as String?, interests = data['interests'] as String?;
  final int level;
  final String? city, interests;
}
class GameResult {
  GameResult(Map<String,dynamic> data)
    : winnerId = data['winner_id'] as String?, myScore = data['my_score'] as int,
      opponentScore = data['opponent_score'] as int, myHits = data['my_hits'] as int,
      opponentHits = data['opponent_hits'] as int, city = data['city'] as String?,
      interests = data['interests'] as String?;
  final String? winnerId, city, interests;
  final int myScore, opponentScore, myHits, opponentHits;
}
class RoomSnapshot {
  RoomSnapshot(Map<String, dynamic> data)
    : room = data['room'] == null ? null : GameRoom(Map<String, dynamic>.from(data['room'] as Map)),
      serverNow = DateTime.parse(data['server_now'] as String), myReady = data['my_ready'] as bool? ?? false;
  final bool myReady;
  final GameRoom? room;
  final DateTime serverNow;
}

String newMessageRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}
class ChatMessage {
  ChatMessage(Map<String,dynamic> data)
    : id = data['id'] as String, senderId = data['sender_id'] as String,
      requestId = data['request_id'] as String, body = data['body'] as String;
  final String id, senderId, requestId, body;
}
class MessagePage {
  const MessagePage(this.messages, this.hasMore);
  final List<ChatMessage> messages;
  final bool hasMore;
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
    final rows = await client.rpc('matches_page_v2', params: before?.toParams() ?? {});
    return decodeFeedPage<Connection>(rows as List, (r) => Connection(
      r['id'] as String, r['other_id'] as String, r['display_name'] as String, photoPath: r['photo_path'] as String?,
    ));
  }

  Future<Uint8List> downloadPhoto(String path) => client.storage.from('profile-photos').download(path);

  Future<String> uploadPhoto(Uint8List bytes, {required String expectedUserId}) async {
    if (userId != expectedUserId) throw const AuthException('Session changed');
    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256));
    id[6] = (id[6] & 15) | 64;
    id[8] = (id[8] & 63) | 128;
    final hex = id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final uuid = '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
    final path = '$expectedUserId/$uuid.jpg';
    final bucket = client.storage.from('profile-photos');
    await bucket.uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    String? previous;
    try {
      if (userId != expectedUserId) throw const AuthException('Session changed');
      previous = await client.rpc('set_profile_photo', params: {'p_path': path}) as String?;
    } catch (_) {
      // Storage policy refuses removal if a response was lost after attachment.
      try { await bucket.remove([path]); } catch (_) {}
      rethrow;
    }
    if (previous != null && previous != path) {
      try { await bucket.remove([previous]); } catch (_) { /* Account deletion also cleans leftovers. */ }
    }
    return path;
  }

  Future<void> removePhoto({required String expectedUserId}) async {
    if (userId != expectedUserId) throw const AuthException('Session changed');
    await client.rpc('set_profile_photo', params: {'p_path': null});
    final bucket = client.storage.from('profile-photos');
    final files = await bucket.list(path: expectedUserId);
    final paths = files.where((f) => f.name.endsWith('.jpg') && !f.name.contains('/')).map((f) => '$expectedUserId/${f.name}').toList();
    if (paths.isNotEmpty) await bucket.remove(paths);
  }

  Future<RoomSnapshot> gameRoom(String matchId, {String action = 'read', String? roomId}) async {
    final data = await client.rpc('game_room_action', params: {
      'p_match': matchId, 'p_action': action, 'p_room': roomId,
    });
    return RoomSnapshot(Map<String, dynamic>.from(data as Map));
  }

  Future<void> signOutLocal() => client.auth.signOut(scope: SignOutScope.local);
  Future<bool> accountRestricted() async => await client.rpc('account_restricted') as bool;
  Future<FeedPage<SanctionAppeal>> ownSanctions({FeedCursor? before}) async {
    final data=await client.rpc('own_sanctions',params:{'p_before_time':before?.createdAt,'p_before_id':before?.id});
    return decodeFeedPage<SanctionAppeal>(data as List,SanctionAppeal.new);
  }
  Future<void> submitAppeal(String sanctionId,String body) async {
    await client.rpc('submit_sanction_appeal',params:{'p_sanction':sanctionId,'p_body':body});
  }
  Future<FeedPage<SanctionAppeal>> moderationAppeals({bool reviewed=false,FeedCursor? before}) async {
    final data=await client.rpc('moderation_appeals',params:{'p_reviewed':reviewed,'p_before_time':before?.createdAt,'p_before_id':before?.id});
    return decodeFeedPage<SanctionAppeal>(data as List,SanctionAppeal.new);
  }
  Future<void> reviewAppeal(String appealId,String decision,String response) async {
    await client.rpc('review_sanction_appeal',params:{'p_appeal':appealId,'p_decision':decision,'p_response':response});
  }

  Future<bool> moderationAccess() async => await client.rpc('moderation_access') as bool;
  Future<FeedPage<ModerationReport>> moderationReports({String status='pending',FeedCursor? before}) async {
    final data=await client.rpc('moderation_reports',params:{'p_status':status,'p_before_time':before?.createdAt,'p_before_id':before?.id});
    return decodeFeedPage<ModerationReport>(data as List,ModerationReport.new);
  }
  Future<void> reviewReport(String reportId,String decision,String note) async {
    await client.rpc('review_report',params:{'p_report':reportId,'p_decision':decision,'p_note':note});
  }

  Future<void> suspendReportedAccount(String reportId,int hours,String reason) async {
    await client.rpc('suspend_reported_account',params:{'p_report':reportId,'p_hours':hours,'p_reason':reason});
  }
  Future<void> liftAccountSanction(String id,String reason) async {
    await client.rpc('lift_account_sanction',params:{'p_sanction':id,'p_reason':reason});
  }
  Future<FeedPage<ModerationSanction>> moderationSanctions({FeedCursor? before}) async {
    final data=await client.rpc('moderation_sanctions',params:{'p_before_time':before?.createdAt,'p_before_id':before?.id});
    return decodeFeedPage<ModerationSanction>(data as List,ModerationSanction.new);
  }

  Future<DiscoveryPreferences> discoveryPreferences() async => DiscoveryPreferences(Map<String,dynamic>.from(await client.rpc('get_discovery_preferences') as Map));
  Future<void> saveDiscoveryPreferences(int minAge,int? maxAge,{required String expectedUserId}) async {
    if(userId!=expectedUserId)throw const AuthException('Session changed');
    await client.rpc('set_discovery_preferences',params:{'p_min':minAge,'p_max':maxAge});
  }

  Future<MatchUnlocks> matchUnlocks(String matchId) async {
    final data = await client.rpc('match_unlocks', params: {'p_match': matchId});
    return MatchUnlocks(Map<String,dynamic>.from(data as Map));
  }

  Future<GameResult?> gameResult(String roomId, {bool finalize = false}) async {
    final dynamic data;
    if (finalize) {
      final response = await client.functions.invoke('finish-round', body: {'room_id': roomId});
      data = response.data;
    } else {
      data = await client.rpc('game_result', params: {'p_room': roomId});
    }
    return data['status'] == 'completed' ? GameResult(Map<String,dynamic>.from(data as Map)) : null;
  }

  Future<void> submitGameInput(String roomId, int sequence, List<int> flaps, {required String expectedUserId}) async {
    if (userId != expectedUserId) throw const AuthException('Session changed');
    final data = await client.rpc('submit_game_input', params: {
      'p_room': roomId, 'p_sequence': sequence, 'p_flaps': flaps,
    });
    if (userId != expectedUserId || data['sequence'] != sequence) throw StateError('Input acknowledgement mismatch');
  }

  Future<MessagePage> messages(String matchId, {String? before, String? after}) async {
    final data = await client.rpc('messages_page', params: {'p_match': matchId, 'p_before': before, 'p_after': after});
    return MessagePage((data['messages'] as List).map((r) => ChatMessage(Map<String,dynamic>.from(r as Map))).toList(), data['has_more'] as bool);
  }
  Future<ChatMessage> sendMessage(String matchId, String requestId, String body) async {
    final data = await client.rpc('send_message', params: {'p_match': matchId, 'p_request': requestId, 'p_body': body});
    return ChatMessage(Map<String,dynamic>.from(data as Map));
  }

  Future<void> unmatch(String matchId) async {
    await client.rpc('unmatch', params: {'p_match': matchId});
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
  if (error is StorageException) return 'Fotoğraf işlemi tamamlanamadı. Bağlantını kontrol edip tekrar dene.';
  if (error is FunctionException) {
    final details = error.details;
    final code = details is Map ? details['error'] : null;
    if (code == 'DELETE_IN_PROGRESS') return 'Hesap silme işlemi sürüyor. Birkaç dakika sonra tekrar dene.';
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
      case 'CHAT_UNAVAILABLE':
        return 'Bu sohbet artık erişilebilir değil. Eşleşmelerini yenile.';
      case 'MESSAGE_LIMIT':
        return 'Mesaj gönderme sınırına ulaştın. Bir dakika sonra tekrar dene.';
      case 'INVALID_MESSAGE':
        return 'Mesaj 1–1000 karakter olmalı.';
      case 'MESSAGE_CONFLICT':
        return 'Bu gönderim farklı içerikle kullanılmış. Sohbeti yeniden aç.';
      case 'ROOM_UNAVAILABLE':
        return 'Bu oyun odasına artık erişilemiyor. Eşleşmelerini yenile.';
      case 'ROOM_ACTION_FORBIDDEN':
        return 'Bu davete yalnızca karşı taraf yanıt verebilir.';
      case 'INVITE_LIMIT':
        return 'Son 24 saatte 20 oyun daveti sınırına ulaştın.';
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
