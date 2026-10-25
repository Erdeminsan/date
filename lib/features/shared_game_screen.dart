import 'dart:async';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import '../game/engine.dart';
import '../game/flight_game.dart';
import '../game/shared_round.dart';

class SharedGameScreen extends StatefulWidget {
  const SharedGameScreen({super.key, required this.backend, required this.connection,
    required this.snapshot, required this.roundTrip});
  final Backend backend;
  final Connection connection;
  final RoomSnapshot snapshot;
  final Duration roundTrip;
  @override
  State<SharedGameScreen> createState() => _SharedGameScreenState();
}
class _SharedGameScreenState extends State<SharedGameScreen> with WidgetsBindingObserver {
  late final SharedRound round;
  late final FlightGame game;
  late final String owner;
  Timer? timer;
  String? notice;
  bool stopped = false, checking = false;
  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
    final room = widget.snapshot.room!;
    round = SharedRound(seed: room.seed!, startsAt: room.startsAt!, serverNow: widget.snapshot.serverNow, roundTrip: widget.roundTrip);
    game = FlightGame(shared: round, onFinished: (score) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || stopped) return;
        game.pauseEngine(); timer?.cancel();
        setState(() { stopped = true; notice = 'Tur bitti. Yerel skorun: $score. Sunucu skor doğrulaması henüz bağlı değil; profil bilgisi açılmadı.'; });
      });
    });
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    if (round.aborted || room.engineVersion != GameEngine.version) {
      WidgetsBinding.instance.addPostFrameCallback((_) => stop('Bu tura zamanında bağlanılamadı. Yeni davet gönder.'));
    }
  }
  Future<void> check() async {
    if (stopped || checking) return;
    checking = true;
    try {
      if (round.aborted || widget.backend.userId != owner) throw StateError('Round unavailable');
      final result = await widget.backend.gameRoom(widget.connection.id, roomId: widget.snapshot.room!.id).timeout(const Duration(seconds: 4));
      if (!mounted || stopped) return;
      if (result.room == null || !['countdown','running','awaiting_result'].contains(result.room!.status)) {
        await stop('Tur kapandı veya iptal edildi.');
      }
    } catch (_) {
      await stop('Bağlantı doğrulanamadı. Tur iptal edildi; bilgi açılmadı.');
    } finally { checking = false; }
  }
  Future<void> stop(String text) async {
    if (!mounted || stopped) return;
    round.cancel(); game.pauseEngine(); timer?.cancel();
    setState(() { stopped = true; notice = text; });
    try {
      if (widget.backend.userId == owner) await widget.backend.gameRoom(widget.connection.id, action: 'cancel', roomId: widget.snapshot.room!.id).timeout(const Duration(seconds: 4));
    } catch (_) { /* Server expiry closes an unreachable room. */ }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop('Uygulama arka plana geçti. Bu tur iptal edildi.');
  }
  @override
  void dispose() {
    timer?.cancel(); round.cancel(); game.pauseEngine();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: stopped,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) stop('Turdan ayrıldın. Bilgi açılmadı.'); },
    child: Scaffold(
      appBar: AppBar(title: Text('${widget.connection.name} · Ortak tur')),
      body: SafeArea(child: Column(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('45 saniye · Aynı engeller · Uçmak için dokun')),
        Expanded(child: GestureDetector(onTapDown: stopped ? null : (_) => game.flap(),
          behavior: HitTestBehavior.opaque, child: ClipRect(child: GameWidget(game: game)))),
        if (notice != null) Padding(padding: const EdgeInsets.all(16), child: Text(notice!)),
        if (stopped) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Odaya dön'))
        else TextButton(onPressed: () => stop('Tur iptal edildi. Bilgi açılmadı.'), child: const Text('Turdan ayrıl')),
      ])),
    ),
  );
}
