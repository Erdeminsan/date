import 'package:flutter/material.dart';
import '../backend/repository.dart';

typedef Authenticate =
    Future<String?> Function(String email, String password, bool signup);

class AuthPanel extends StatefulWidget {
  const AuthPanel({
    super.key,
    required this.authenticate,
    required this.resend,
    this.resetPassword,
  });
  final Future<void> Function(String email)? resetPassword;
  final Authenticate authenticate;
  final Future<void> Function(String email) resend;
  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool signup = false, busy = false, adult = false;
  String? notice;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (signup && !adult) {
      setState(() => notice = '18 yaş ve üzeri olduğunu onayla.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      final result = await widget.authenticate(
        email.text.trim(),
        password.text,
        signup,
      );
      if (mounted) setState(() => notice = result);
    } catch (e) {
      if (mounted) setState(() => notice = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    if (!email.text.contains('@')) {
      setState(() => notice = 'Geçerli bir e-posta yaz.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.resend(email.text.trim());
      if (mounted)
        setState(
          () =>
              notice = 'Uygun bir kayıt varsa doğrulama e-postası gönderildi.',
        );
    } catch (e) {
      if (mounted) setState(() => notice = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (busy) return;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      setState(() => notice = 'Şifre sıfırlamak için geçerli bir e-posta gir.');
      return;
    }
    setState(() {
      busy = true;
      notice = null;
    });
    try {
      await widget.resetPassword!(email.text.trim());
      if (mounted)
        setState(
          () =>
              notice =
                  'Uygun bir hesap varsa sıfırlama e-postası gönderildi. Bağlantıyı bu cihazda aç.',
        );
    } catch (e) {
      if (mounted) setState(() => notice = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('playmatch'),
      actions: const [
        Padding(padding: EdgeInsets.all(16), child: Text('KAPALI BETA')),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 28),
                const Icon(
                  Icons.bolt_rounded,
                  size: 72,
                  color: Color(0xFFB8A2FF),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Bir oyunla\nbaşlasın.',
                  style: TextStyle(
                    fontSize: 44,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  signup
                      ? 'Hesabını oluştur, profilini tamamla ve keşfet.'
                      : 'Hikâyene kaldığın yerden devam et.',
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-posta'),
                  validator:
                      (v) =>
                          v != null &&
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(v.trim())
                              ? null
                              : 'Geçerli bir e-posta gir.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  autofillHints: [
                    signup ? AutofillHints.newPassword : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(labelText: 'Şifre'),
                  validator:
                      (v) =>
                          (v ?? '').length < (signup ? 8 : 1)
                              ? (signup
                                  ? 'En az 8 karakter kullan.'
                                  : 'Şifreni gir.')
                              : null,
                  onFieldSubmitted: (_) {
                    if (!busy) submit();
                  },
                ),
                if (signup)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: adult,
                    onChanged:
                        busy ? null : (v) => setState(() => adult = v ?? false),
                    title: const Text('18 yaşında veya daha büyüğüm.'),
                  ),
                const SizedBox(height: 20),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(notice!, key: const Key('auth-notice')),
                  ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'İşleniyor…'
                        : (signup ? 'Hesap oluştur' : 'Giriş yap'),
                  ),
                ),
                TextButton(
                  onPressed:
                      busy
                          ? null
                          : () => setState(() {
                            signup = !signup;
                            notice = null;
                          }),
                  child: Text(
                    signup ? 'Hesabım var · Giriş yap' : 'Yeni hesap oluştur',
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : resend,
                  child: const Text('Doğrulama e-postasını tekrar gönder'),
                ),
                if (!signup && widget.resetPassword != null)
                  TextButton(
                    onPressed: busy ? null : resetPassword,
                    child: const Text('Şifremi unuttum'),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Kapalı test sürümü. Eşleş, mesajlaş ve Sky Hop oyna.',
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
