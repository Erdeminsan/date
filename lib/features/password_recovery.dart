import 'package:flutter/material.dart';
import '../backend/repository.dart';

class PasswordRecovery extends StatefulWidget {
  const PasswordRecovery({super.key, required this.save, required this.finish, this.cancel});
  final Future<void> Function(String password) save;
  final Future<void> Function() finish;
  final Future<void> Function()? cancel;
  @override
  State<PasswordRecovery> createState() => _PasswordRecoveryState();
}

class _PasswordRecoveryState extends State<PasswordRecovery> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController();
  bool busy = false, saved = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || (!saved && !form.currentState!.validate())) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!saved) {
        await widget.save(password.text);
        password.clear();
        if (!mounted) return;
        setState(() => saved = true);
      }
      await widget.finish();
    } catch (e) {
      if (mounted)
        setState(
          () =>
              error =
                  saved
                      ? 'Şifren değişti. Oturumu kapatmak için tekrar dene.'
                      : friendlyError(e),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      await widget.cancel!();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yeni şifre')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  saved
                      ? 'Şifren değişti. Yeni şifrenle tekrar giriş yap.'
                      : 'Hesabın için yeni bir şifre belirle.',
                ),
                const SizedBox(height: 24),
                if (!saved) ...[
                  TextFormField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'Yeni şifre'),
                    validator:
                        (v) =>
                            (v ?? '').length < 8
                                ? 'En az 8 karakter kullan.'
                                : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Yeni şifre tekrar',
                    ),
                    validator:
                        (v) =>
                            v != password.text ? 'Şifreler aynı olmalı.' : null,
                  ),
                ],
                const SizedBox(height: 24),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(error!),
                  ),
                if (!saved && widget.cancel != null)
                  TextButton(onPressed: busy ? null : cancel, child: const Text('Vazgeç ve girişe dön')),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'İşleniyor…'
                        : saved
                        ? 'Giriş ekranına dön'
                        : 'Şifreyi kaydet',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
