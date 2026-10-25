import 'dart:async';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import '../game/engine.dart';
import '../game/flight_game.dart';
import '../game/shared_round.dart';
import '../game/input_sender.dart';
import 'game_result_screen.dart';

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
  Timer? timer, inputTimer;
  late final InputSender sender;
  String? notice;
  bool stopped = false, checking = false;
  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
    final room = widget.snapshot.room!;
    round = SharedRound(seed: room.seed!, startsAt: room.startsAt!, serverNow: widget.snapshot.serverNow, roundTrip: widget.roundTrip);
    sender = InputSender((sequence, flaps) => widget.backend.submitGameInput(room.id, sequence, flaps, expectedUserId: owner));
    game = FlightGame(shared: round, onFinished: (score) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || stopped) return;
        game.pauseEngine();
        setState(() { notice = 'Tur bitti. Girdiler sunucuya gönderiliyor…'; });
        upload();
      });
    });
    WidgetsBinding.instance.addObserver(this);
    inputTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => upload());
    timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    if (round.aborted || room.engineVersion != GameEngine.version || room.inputProtocol != InputSender.protocol) {
      WidgetsBinding.instance.addPostFrameCallback((_) => stop('Bu tura zamanında bağlanılamadı. Yeni davet gönder.'));
    }
  }
  Future<void> upload() async {
    if (stopped || !mounted) return;
    if (round.aborted || widget.backend.userId != owner) {
      await stop('Tur bağlantısı kesildi. Bilgi açılmadı.'); return;
    }
    await sender.pump(completedTick: round.round.engine.tick, inputs: round.round.inputs,
      elapsedMs: round.estimatedNow.difference(widget.snapshot.room!.startsAt!).inMilliseconds);
    if (!mounted || stopped) return;
    if (sender.cancelled && round.round.finished) {
      openResult();
    } else if (sender.cancelled) {
      await stop('Oyun girdileri zamanında iletilemedi. Tur iptal edildi.');
    } else if (sender.complete) {
      openResult();
    }
  }
  void openResult() {
    if (!mounted || stopped) return;
    inputTimer?.cancel(); timer?.cancel(); game.pauseEngine();
    setState(() { stopped = true; notice = 'Tur tamamlandı. Sonucunu kontrol edebilirsin.'; });
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => GameResultScreen(backend: widget.backend, roomId: widget.snapshot.room!.id)));
  }
  Future<void> check() async {
    if (stopped || checking) return;
    checking = true;
    try {
      if (round.aborted || widget.backend.userId != owner) throw StateError('Round unavailable');
      final result = await widget.backend.gameRoom(widget.connection.id, roomId: widget.snapshot.room!.id).timeout(const Duration(seconds: 4));
      if (!mounted || stopped) return;
      if (result.room?.status == 'completed' && round.round.finished) { openResult(); return; }
      if (result.room == null || !['countdown','running','awaiting_result'].contains(result.room!.status)) {
        await stop('Tur kapandı veya iptal edildi.');
      }
    } catch (_) {
      await stop(round.round.finished ? 'Bağlantı doğrulanamadı. Sonucu odadan kontrol edebilirsin.' : 'Bağlantı doğrulanamadı. Tur iptal edildi; bilgi açılmadı.');
    } finally { checking = false; }
  }
  Future<void> stop(String text) async {
    if (!mounted || stopped) return;
    round.cancel(); sender.cancel(); game.pauseEngine(); timer?.cancel(); inputTimer?.cancel();
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
    timer?.cancel(); inputTimer?.cancel(); sender.cancel(); round.cancel(); game.pauseEngine();
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
        if (stopped && round.round.finished) TextButton(onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => GameResultScreen(backend: widget.backend, roomId: widget.snapshot.room!.id))), child: const Text('Sonucu gör')),
        if (stopped) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Odaya dön'))
        else TextButton(onPressed: () => stop('Tur iptal edildi. Bilgi açılmadı.'), child: const Text('Turdan ayrıl')),
      ])),
    ),
  );
}
