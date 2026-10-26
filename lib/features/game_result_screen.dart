import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';

class GameResultScreen extends StatefulWidget {
  const GameResultScreen({super.key, required this.backend, required this.roomId});
  final Backend backend;
  final String roomId;
  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}
class _GameResultScreenState extends State<GameResultScreen> with WidgetsBindingObserver {
  late final String owner;
  Timer? timer;
  GameResult? result;
  String? error;
  bool busy = false, foreground = true;
  int generation = 0;
  @override
  void initState() {
    super.initState(); owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this); read();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (foreground && error == null && ModalRoute.of(context)?.isCurrent == true) read();
    });
  }
  Future<void> read() async {
    if (busy || !foreground) return;
    final request = ++generation;
    setState(() { busy = true; error = null; });
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      final value = await widget.backend.gameResult(widget.roomId, finalize: result == null).timeout(const Duration(seconds: 6));
      if (!mounted || !foreground || request != generation) return;
      if (widget.backend.userId != owner) throw StateError('Session changed');
      setState(() => result = value);
    } catch (_) {
      if (mounted && request == generation) setState(() { result = null; error = 'Sonuç alınamadı. Bağlantını kontrol edip tekrar dene.'; });
    } finally { if (mounted && request == generation) setState(() => busy = false); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      generation++;
      setState(() { result = null; error = null; busy = false; });
    } else { read(); }
  }
  @override
  void dispose() { generation++; timer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final r = result;
    return Scaffold(appBar: AppBar(title: const Text('Tur sonucu')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) ...[Text(error!), FilledButton(onPressed: busy ? null : read, child: const Text('Tekrar dene'))]
        else if (r == null) const Text('İki oyuncunun girdileri ve tur sonucu doğrulanıyor…')
        else ...[
          Text(r.winnerId == null ? 'Berabere' : r.winnerId == owner ? 'Kazandın!' : 'Rakibin kazandı', style: const TextStyle(fontSize: 28)),
          Text('Sen: ${r.myScore} · Rakibin: ${r.opponentScore}'),
          Text('Çarpışma: ${r.myHits} · Rakibin: ${r.opponentHits}'),
          const SizedBox(height: 24),
          const Text('Bu eşleşmede açtığın bilgiler'),
          Text(r.city == null ? 'Şehir · İlk galibiyetinde açılır' : 'Şehir: ${r.city}'),
          Text(r.interests == null ? 'İlgi alanları · İkinci galibiyetinde açılır' : 'İlgi alanları: ${r.interests!.isEmpty ? "Henüz eklenmemiş" : r.interests}'),
          const SizedBox(height: 12),
          const Text('Yalnız kazanan ilerler. Beraberlik yeni bilgi açmaz.'),
        ],
      ]));
  }
}
