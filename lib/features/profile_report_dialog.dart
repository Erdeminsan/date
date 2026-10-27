import 'package:flutter/material.dart';
import '../backend/repository.dart';

class ProfileReportDialog extends StatefulWidget {
  const ProfileReportDialog({super.key, required this.backend, required this.targetId});
  final Backend backend;
  final String targetId;
  @override
  State<ProfileReportDialog> createState() => _ProfileReportDialogState();
}

class _ProfileReportDialogState extends State<ProfileReportDialog> with WidgetsBindingObserver {
  final reason = TextEditingController();
  final requestId = newMessageRequestId();
  late final String owner;
  String? pendingReason, error;
  bool busy = false, foreground = true;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> submit() async {
    if (busy || !foreground || reason.text.trim().length < 5) return;
    pendingReason ??= reason.text.trim();
    final current = ++generation;
    setState(() { busy = true; error = null; });
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      await widget.backend.report(widget.targetId, pendingReason!, requestId: requestId)
          .timeout(const Duration(seconds: 15));
      if (!mounted || current != generation || !foreground) return;
      if (widget.backend.userId != owner) throw StateError('Session changed');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted && current == generation) {
        setState(() => error = 'Şikâyet doğrulanamadı. Aynı isteği tekrar deneyebilirsin.');
      }
    } finally {
      if (mounted && current == generation) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    generation++;
    setState(() {
      busy = false;
      if (pendingReason != null) error = 'Gönderimin sonucu doğrulanmadı. Aynı isteği tekrar deneyebilirsin.';
    });
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Profili şikâyet et'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: reason, readOnly: pendingReason != null,
          maxLength: 1000, maxLines: 3, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Nedenini yaz (en az 5 karakter)')),
        if (error != null) Text(error!),
      ])),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.of(context).pop(false), child: const Text('Kapat')),
        FilledButton(onPressed: busy || !foreground || reason.text.trim().length < 5 ? null : submit,
          child: Text(busy ? 'Gönderiliyor…' : pendingReason == null ? 'Gönder' : 'Aynı şikâyeti tekrar dene')),
      ],
    ),
  );
}
