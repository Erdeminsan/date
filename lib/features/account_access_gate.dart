import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import 'appeals_screen.dart';
import 'member_home.dart';

/// Owns the authenticated navigation stack so access loss removes covered routes
/// and dialogs as well as the home screen. Server authorization remains decisive.
class AccountAccessGate extends StatefulWidget {
  const AccountAccessGate({super.key, required this.backend, this.memberBuilder});
  final Backend backend;
  final WidgetBuilder? memberBuilder;
  @override
  State<AccountAccessGate> createState() => _AccountAccessGateState();
}

class _AccountAccessGateState extends State<AccountAccessGate> with WidgetsBindingObserver {
  late final String owner;
  Timer? timer;
  var navigatorKey = GlobalKey<NavigatorState>();
  bool? restricted;
  bool foreground = true, checking = false, validating = true;
  int generation = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this);
    check();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => check());
  }

  Future<void> check() async {
    if (!foreground || checking) return;
    checking = true;
    final request = ++generation;
    try {
      if (widget.backend.userId != owner) throw StateError('Session changed');
      final next = await widget.backend.accountRestricted().timeout(const Duration(seconds: 6));
      if (!mounted || request != generation || !foreground) return;
      if (widget.backend.userId != owner) throw StateError('Session changed');
      setState(() {
        if (restricted != next) navigatorKey = GlobalKey<NavigatorState>();
        restricted = next; validating = false; error = null;
      });
    } catch (_) {
      if (mounted && request == generation) setState(() {
        restricted = null; navigatorKey = GlobalKey<NavigatorState>(); validating = false;
        error = 'Hesap durumu doğrulanamadı. Bağlantını kontrol edip tekrar dene.';
      });
    } finally { if (request == generation) checking = false; }
  }

  Future<void> signOut() async {
    try { await widget.backend.signOutLocal(); }
    catch (_) { if (mounted) setState(() => error = 'Çıkış yapılamadı. Tekrar dene.'); }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    generation++; checking = false;
    setState(() => validating = true);
    if (foreground) check();
  }

  @override
  void dispose() {
    generation++; timer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
    if (restricted != null) Offstage(
      offstage: !foreground || validating,
      child: NavigatorPopHandler<Object?>(
        onPopWithResult: (result) => navigatorKey.currentState?.pop(result),
        child: Navigator(
          key: navigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (context) => restricted!
              ? AppealsScreen(backend: widget.backend, restricted: true)
              : widget.memberBuilder?.call(context) ?? MemberHome(backend: widget.backend)),
        ),
      ),
    ),
    if (restricted == null || !foreground || validating) Scaffold(
      body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error == null) const CircularProgressIndicator() else ...[
            Text(error!),
            TextButton(onPressed: check, child: const Text('Tekrar dene')),
            TextButton(onPressed: signOut, child: const Text('Çıkış yap')),
          ],
        ],
      )))),
    ),
  ]);
}
