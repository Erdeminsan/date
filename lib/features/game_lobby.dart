import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import '../game/engine.dart';
import 'shared_game_screen.dart';

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
  final opened = <String>{};
  late final String owner;
  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
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
    final watch = Stopwatch()..start();
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      final value = await widget.backend.gameRoom(widget.connection.id, action: action, roomId: roomId);
      watch.stop();
      if (!mounted || request != generation) return;
      if (widget.backend.userId != owner) throw StateError('Session changed');
      setState(() => snapshot = value);
      final room = value.room;
      if (foreground && ModalRoute.of(context)?.isCurrent == true && room != null &&
          ['countdown','running'].contains(room.status) && !opened.contains(room.id)) {
        if (room.seed == null || room.startsAt == null || room.engineVersion != GameEngine.version) {
          throw StateError('Unsupported game version');
        }
        opened.add(room.id);
        await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => SharedGameScreen(
          backend: widget.backend, connection: widget.connection, snapshot: value, roundTrip: watch.elapsed,
        )));
      }
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
      'accepted': 'Davet kabul edildi', 'countdown': 'Ortak geri sayım',
      'running': 'Tur sürüyor', 'awaiting_result': 'Tur bitti · Sonuç doğrulaması henüz bağlı değil', 'declined': 'Davet reddedildi',
      'cancelled': 'Davet iptal edildi', 'expired': 'Davetin süresi doldu'};
    return Scaffold(
      appBar: AppBar(title: Text('${widget.connection.name} · Sky Hop')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('Oyun daveti', style: TextStyle(fontSize: 28)),
        const SizedBox(height: 16),
        const Text('İkiniz de hazır olduğunuzda 5 saniyelik geri sayımla aynı engellerde oynarsınız. Sonuç doğrulaması henüz bağlı değil; bu tur profil bilgisi açmaz.'),
        const SizedBox(height: 24),
        if (busy) const LinearProgressIndicator(),
        if (error != null) ...[
          Text(error!),
          FilledButton(onPressed: busy ? null : () => refresh(), child: const Text('Tekrar dene')),
        ] else if (snapshot != null) ...[
          Text(room == null ? 'Aktif davet yok' : labels[room.status] ?? 'Oda güncelleniyor'),
          if (room?.status == 'accepted') ...[
            const Text('İki oyuncu da hazır olmalı. Bekleme odası 2 dakika sonra kapanır.'),
            FilledButton(onPressed: busy || snapshot!.myReady ? null : () => refresh('ready'),
              child: Text(snapshot!.myReady ? 'Hazırsın · Karşı taraf bekleniyor' : 'Hazırım')),
          ],
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
