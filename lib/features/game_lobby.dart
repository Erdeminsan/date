import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';

class GameLobby extends StatefulWidget {
  const GameLobby({super.key, required this.backend, required this.connection});
  final Backend backend;
  final Connection connection;
  @override
  State<GameLobby> createState() => _GameLobbyState();
}

class _GameLobbyState extends State<GameLobby> with WidgetsBindingObserver {
  Timer? timer;
  RoomSnapshot? snapshot;
  String? error;
  bool busy = false, foreground = true;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground && error == null && ModalRoute.of(context)?.isCurrent == true) refresh();
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) refresh();
  }
  @override
  void dispose() {
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> refresh([String action = 'read']) async {
    if (busy) return;
    final request = ++generation;
    final roomId = action == 'read' || action == 'invite' ? null : snapshot?.room?.id;
    setState(() { busy = true; error = null; });
    try {
      final value = await widget.backend.gameRoom(widget.connection.id, action: action, roomId: roomId);
      if (mounted && request == generation) setState(() => snapshot = value);
    } catch (e) {
      if (mounted && request == generation) setState(() { error = friendlyError(e); snapshot = null; });
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final room = snapshot?.room;
    final incoming = room != null && room.inviterId != widget.backend.userId;
    final labels = {'invited': incoming ? 'Oyun daveti aldın' : 'Davet gönderildi',
      'accepted': 'Davet kabul edildi', 'declined': 'Davet reddedildi',
      'cancelled': 'Davet iptal edildi', 'expired': 'Davetin süresi doldu'};
    return Scaffold(
      appBar: AppBar(title: Text('${widget.connection.name} · Sky Hop')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Oyun daveti', style: TextStyle(fontSize: 28)),
        const SizedBox(height: 16),
        const Text('Davet 60 saniye geçerlidir. Bu sürümde davetleşebilirsin; ortak tur henüz açılmadı. Davet kabulü profil bilgisi açmaz.'),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(error!),
          FilledButton(onPressed: busy ? null : () => refresh(), child: const Text('Tekrar dene')),
        ] else if (snapshot != null) ...[
          Text(room == null ? 'Aktif davet yok' : labels[room.status] ?? 'Oda güncelleniyor'),
          if (room?.status == 'accepted')
            const Text('Ortak oyun bağlantısı sonraki sürümde açılacak. Bekleme odası 2 dakika sonra kapanır.'),
          if (room == null || !room.active)
            FilledButton(onPressed: busy ? null : () => refresh('invite'), child: const Text('Oyun daveti gönder')),
          if (room?.status == 'invited' && incoming) ...[
            FilledButton(onPressed: busy ? null : () => refresh('accept'), child: const Text('Kabul et')),
            TextButton(onPressed: busy ? null : () => refresh('decline'), child: const Text('Reddet')),
          ],
          if (room != null && room.active)
            TextButton(onPressed: busy ? null : () => refresh('cancel'), child: const Text('Daveti iptal et')),
        ],
        TextButton(onPressed: busy ? null : () => refresh(), child: const Text('Yenile')),
      ]),
    );
  }
}
