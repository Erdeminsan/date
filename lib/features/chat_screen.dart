import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import 'game_lobby.dart';
import 'match_details_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.backend, required this.connection});
  final Backend backend;
  final Connection connection;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final input = TextEditingController();
  late final String owner;
  final messages = <String,ChatMessage>{};
  Timer? timer;
  String? newest, oldest, error, sendError, requestId, pendingBody;
  bool reading = false, sending = false, hasOlder = false, foreground = true;
  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this);
    read();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (foreground && error == null && ModalRoute.of(context)?.isCurrent == true) read();
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) read();
  }
  @override
  void dispose() {
    timer?.cancel(); input.dispose(); WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> read({bool older = false}) async {
    if (reading) return;
    setState(() { reading = true; error = null; });
    final initial = newest == null;
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      final page = await widget.backend.messages(widget.connection.id,
        before: older ? oldest : null, after: older || initial ? null : newest);
      if (!mounted) return;
      if (widget.backend.userId != owner) throw StateError('Session changed');
      setState(() {
        for (final m in page.messages) { messages[m.id] = m; }
        if (messages.isNotEmpty) {
          final ids = messages.keys.toList()..sort((a,b) => BigInt.parse(a).compareTo(BigInt.parse(b)));
          newest = ids.last;
          if (older || initial) oldest = ids.first;
        }
        if (older || initial) hasOlder = page.hasMore;
        if (!sending && requestId != null && page.messages.any((m) => m.requestId == requestId && m.senderId == owner)) {
          requestId = null; pendingBody = null; sendError = null; input.clear();
        }
      });
    } catch (e) {
      if (mounted) setState(() {
        error = friendlyError(e); messages.clear(); newest = null; oldest = null; hasOlder = false;
      });
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }
  Future<void> send() async {
    if (sending) return;
    final body = pendingBody ?? input.text.trim();
    if (body.isEmpty) return;
    requestId ??= newMessageRequestId(); pendingBody = body;
    setState(() { sending = true; sendError = null; });
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      await widget.backend.sendMessage(widget.connection.id, requestId!, body);
      if (!mounted) return;
      setState(() { requestId = null; pendingBody = null; input.clear(); });
      await read();
    } catch (e) {
      if (mounted) setState(() => sendError = friendlyError(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final ordered = messages.values.toList()..sort((a,b) => BigInt.parse(b.id).compareTo(BigInt.parse(a.id)));
    return Scaffold(
      appBar: AppBar(title: Text(widget.connection.name), actions: [
        IconButton(tooltip: 'Açılan bilgiler', icon: const Icon(Icons.person_outline),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MatchDetailsScreen(backend: widget.backend, connection: widget.connection)))),
        IconButton(tooltip: 'Oyun daveti', icon: const Icon(Icons.sports_esports_outlined),
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => GameLobby(backend: widget.backend, connection: widget.connection)))),
        IconButton(tooltip: 'Sohbeti yenile', onPressed: reading ? null : () => read(), icon: const Icon(Icons.refresh)),
      ]),
      body: SafeArea(child: Column(children: [
        if (reading) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(child: ListView.builder(reverse: true, padding: const EdgeInsets.all(12),
          itemCount: ordered.length + (hasOlder ? 1 : 0), itemBuilder: (context,index) {
            if (index == ordered.length) return TextButton(onPressed: reading ? null : () => read(older: true), child: const Text('Önceki mesajlar'));
            final m = ordered[index];
            return Align(alignment: m.senderId == owner ? Alignment.centerRight : Alignment.centerLeft,
              child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(m.body))));
          })),
        if (sendError != null) Padding(padding: const EdgeInsets.all(8), child: Text(sendError!)),
        Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(controller: input, readOnly: requestId != null || sending,
            minLines: 1, maxLines: 4, maxLength: 1000, decoration: const InputDecoration(hintText: 'Mesaj yaz'))),
          const SizedBox(width: 8),
          FilledButton(onPressed: sending || error != null ? null : send,
            child: Text(sending ? 'Gönderiliyor…' : requestId == null ? 'Gönder' : 'Tekrar dene')),
        ])),
      ])),
    );
  }
}
