import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import 'account_settings.dart' show DeleteAccountDialog;

class AppealsScreen extends StatefulWidget {
  const AppealsScreen({super.key, required this.backend, this.moderator = false, this.restricted = false});
  final Backend backend;
  final bool moderator, restricted;
  @override
  State<AppealsScreen> createState() => _AppealsScreenState();
}

class _AppealsScreenState extends State<AppealsScreen> with WidgetsBindingObserver {
  late final String owner;
  final rows = <SanctionAppeal>[];
  FeedCursor? cursor;
  Timer? timer;
  bool foreground = true, busy = false, checking = false, dialogOpen = false, reviewed = false;
  int generation = 0;
  String? error;

  @override
  void initState() {
    super.initState(); owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this); load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => checkAccess());
  }
  void checkOwner() { if (widget.backend.userId != owner) throw StateError('Session changed'); }
  void clear() {
    generation++;
    if (dialogOpen) { dialogOpen = false; Navigator.of(context).pop(); }
    setState(() { rows.clear(); cursor = null; busy = false; error = 'Kayıtlara erişilemiyor. Oturumunu ve bağlantını kontrol et.'; });
  }
  Future<void> checkAccess() async {
    if (!foreground || checking) return;
    checking = true;
    try {
      checkOwner();
      if (widget.moderator) {
        if (!await widget.backend.moderationAccess().timeout(const Duration(seconds: 5))) throw StateError('Access lost');
      } else {
        await widget.backend.accountRestricted().timeout(const Duration(seconds: 5));
      }
      checkOwner();
    } catch (_) { if (mounted && foreground) clear(); }
    finally { checking = false; }
  }
  Future<void> load({bool more = false}) async {
    if (busy || !foreground) return;
    final request = ++generation;
    final before = more ? cursor : null;
    setState(() { busy = true; error = null; if (!more) { rows.clear(); cursor = null; } });
    try {
      checkOwner();
      final page = await (widget.moderator
          ? widget.backend.moderationAppeals(reviewed: reviewed, before: before)
          : widget.backend.ownSanctions(before: before)).timeout(const Duration(seconds: 6));
      if (!mounted || request != generation || !foreground) return;
      checkOwner();
      setState(() { final merged = {for (final r in [...rows, ...page.items]) r.id: r}; rows..clear()..addAll(merged.values); cursor = page.next; });
    } catch (_) { if (mounted && request == generation) clear(); }
    finally { if (mounted && request == generation) setState(() => busy = false); }
  }
  Future<void> act(SanctionAppeal row) async {
    var text = '', decision = 'upheld'; dialogOpen = true;
    final accepted = await showDialog<bool>(useRootNavigator: false, context: context,
      builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(widget.moderator ? 'İtiraz kararı' : 'Kısıtlamaya itiraz'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.moderator) ...[
            DropdownButton<String>(isExpanded: true, value: decision, items: const [
              DropdownMenuItem(value: 'upheld', child: Text('Kararı koru')),
              DropdownMenuItem(value: 'lifted', child: Text('İtirazı kabul et')),
            ], onChanged: (v) => update(() => decision = v!)),
            const Text('Yanıt kullanıcıya gösterilir. Kabul bu kaydın kısıtlamasını kaldırır; diğer aktif kayıtları etkilemez.'),
          ] else const Text('Bu kayıt için bir itiraz gönderebilirsin. Gönderdiğin metin sonradan değiştirilemez.'),
          TextField(maxLength: widget.moderator ? 1000 : 2000, maxLines: 4,
            onChanged: (v) => update(() => text = v),
            decoration: InputDecoration(labelText: widget.moderator ? 'Kullanıcıya yanıt (en az 5 karakter)' : 'İtiraz açıklaman (en az 5 karakter)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: text.trim().length < 5 ? null : () => Navigator.pop(context, true),
            child: Text(widget.moderator ? 'Yanıtı kaydet' : 'İtirazı gönder')),
        ],
      )),
    );
    dialogOpen = false;
    if (accepted != true || !mounted || !foreground || busy) return;
    final request = ++generation; setState(() => busy = true);
    try {
      checkOwner();
      await (widget.moderator ? widget.backend.reviewAppeal(row.appealId!, decision, text.trim())
          : widget.backend.submitAppeal(row.sanctionId, text.trim())).timeout(const Duration(seconds: 6));
      if (!mounted || request != generation || !foreground) return;
      checkOwner(); setState(() => busy = false); await load();
    } catch (_) {
      if (mounted && request == generation) { clear(); setState(() => error = 'İşlem doğrulanamadı. Yeni bir metin göndermeden önce listeyi yenileyip kayıt durumunu kontrol et.'); }
    }
  }
  Future<void> signOut() async {
    try { await widget.backend.signOutLocal(); }
    catch (_) { if (mounted) setState(() => error = 'Çıkış yapılamadı. Tekrar dene.'); }
  }
  Future<void> deleteAccount() async {
    dialogOpen = true;
    final backend = widget.backend;
    await showDialog<bool>(useRootNavigator: false, context: context, barrierDismissible: false,
      builder: (_) => DeleteAccountDialog(deleteAccount: (password) async {
        await backend.deleteAccount(password);
        // Completion must still clear this session if access polling removed the dialog.
        await backend.signOutLocal();
      }));
    dialogOpen = false;
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    clear(); if (foreground) load();
  }
  @override
  void dispose() { generation++; timer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.moderator ? 'İtiraz inceleme' : 'Hesap durumu ve itirazlar')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      if (widget.restricted) ...[
        const Text('Hesabın geçici olarak kısıtlı.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const Text('İnceleme sonrası süreli erişim kısıtlaması uygulandı. Keşif, eşleşme, sohbet ve oyun kullanılamaz. Karara katılmıyorsan aşağıdan itiraz gönderebilirsin.'),
      ],
      if (widget.moderator) SegmentedButton<bool>(segments: const [
        ButtonSegment(value: false, label: Text('Bekleyen')), ButtonSegment(value: true, label: Text('Yanıtlanan')),
      ], selected: {reviewed}, onSelectionChanged: busy ? null : (v) { setState(() => reviewed = v.first); load(); }),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      if (!busy && error == null && rows.isEmpty) const Text('Bu listede kayıt yok.'),
      for (final r in rows) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (r.displayName != null) Text(r.displayName!),
        if (widget.moderator && r.internalReason != null) Text('İç gerekçe: ${r.internalReason}'),
        Text(r.active ? 'Aktif kısıtlama' : 'Kısıtlama sona erdi'),
        Text('Planlanan bitiş: ${r.expiresAt.toLocal()}'),
        if (r.body != null) Text('İtiraz: ${r.body}'),
        if (r.appealId != null && r.decision == null) const Text('İtiraz inceleme bekliyor.'),
        if (r.decision != null) ...[
          Text(r.decision == 'lifted' ? 'İtiraz kabul edildi.' : 'İtiraz reddedildi; önceki karar korundu.'),
          Text('Yanıt: ${r.response ?? ''}'),
        ],
        if (widget.moderator && r.decision == null) TextButton(onPressed: busy ? null : () => act(r), child: const Text('İtirazı incele')),
        if (!widget.moderator && r.appealId == null) TextButton(onPressed: busy ? null : () => act(r), child: const Text('İtiraz et')),
      ]))),
      if (cursor != null) TextButton(onPressed: busy ? null : () => load(more: true), child: const Text('Daha fazla kayıt')),
      TextButton(onPressed: busy ? null : load, child: const Text('Yenile')),
      if (widget.restricted) ...[
        TextButton(onPressed: busy ? null : signOut, child: const Text('Çıkış yap')),
        TextButton(onPressed: busy ? null : deleteAccount, child: const Text('Hesabımı sil')),
      ],
    ])),
  );
}
