import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';

class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({super.key, required this.backend, required this.connection});
  final Backend backend;
  final Connection connection;
  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}
class _MatchDetailsScreenState extends State<MatchDetailsScreen> with WidgetsBindingObserver {
  late final String owner;
  Timer? timer;
  MatchUnlocks? details;
  bool busy = false, foreground = true;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState(); owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this); read();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground && error == null && ModalRoute.of(context)?.isCurrent == true) read();
    });
  }
  Future<void> read() async {
    if (busy || !foreground) return;
    final request = ++generation;
    setState(() { busy = true; error = null; });
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      final value = await widget.backend.matchUnlocks(widget.connection.id).timeout(const Duration(seconds: 6));
      if (!mounted || request != generation || !foreground) return;
      if (widget.backend.userId != owner) throw StateError('Session changed');
      setState(() => details = value);
    } catch (_) {
      if (mounted && request == generation) setState(() {
        details = null; error = 'Bilgiler alınamadı. Bağlantını veya eşleşmenin durumunu kontrol et.';
      });
    } finally { if (mounted && request == generation) setState(() => busy = false); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    generation++;
    setState(() { details = null; busy = false; });
    if (foreground) read();
  }
  @override
  void dispose() { generation++; timer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.connection.name} · Açılan bilgiler')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!)
      else if (details != null) ...[
        Text('Açılan alan: ${details!.level}/2', style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 16),
        Text(details!.city == null ? 'Şehir · İlk galibiyetinde açılır' : 'Şehir: ${details!.city}'),
        const SizedBox(height: 12),
        Text(details!.interests == null ? 'İlgi alanları · İkinci galibiyetinde açılır' : 'İlgi alanları: ${details!.interests!.isEmpty ? "Henüz eklenmemiş" : details!.interests}'),
        const SizedBox(height: 24),
        const Text('Kazanılmış erişimin yeni oyunlarda korunur. Eşleşme sona ererse veya engelleme olursa bu bilgilere erişimin kapanır.'),
      ],
      TextButton(onPressed: busy || !foreground ? null : read, child: const Text('Yenile')),
    ]),
  );
}
