import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../backend/repository.dart';
import 'moderation_screen.dart';

class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key, required this.backend});
  final Backend backend;
  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  List<Person> blocked = [];
  bool loading = true, busy = false, deleted = false;
  String? error;
  bool canModerate = false;

  @override
  void initState() {
    super.initState();
    load();
    loadModerationAccess();
  }

  Future<void> loadModerationAccess() async {
    try {
      final owner = widget.backend.userId;
      final allowed = await widget.backend.moderationAccess().timeout(const Duration(seconds: 6));
      if (mounted) setState(() => canModerate = allowed && widget.backend.userId == owner);
    } catch (_) { if (mounted) setState(() => canModerate = false); }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.backend.blockedProfiles();
      if (mounted) setState(() => blocked = rows);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> unblock(Person person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('${person.name} için engeli kaldır?'),
            content: const Text(
              'Eski beğeniler ve eşleşme geri gelmez. Karşı tarafın koyduğu bir engel varsa devam eder.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Engeli kaldır'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.backend.unblock(person.id);
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leaveDeletedAccount() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.backend.client.auth.signOut(scope: SignOutScope.local);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted)
        setState(
          () =>
              error =
                  'Hesabın silindi. Bu cihazdaki oturumu kapatmak için tekrar dene.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) =>
              DeleteAccountDialog(deleteAccount: widget.backend.deleteAccount),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deleted = true);
    await leaveDeletedAccount();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !deleted,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Hesap ayarları'),
        automaticallyImplyLeading: !busy && !deleted,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (deleted) ...[
              const Text('Hesabın silindi.', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : leaveDeletedAccount,
                child: const Text('Giriş ekranına dön'),
              ),
            ] else ...[
              if (canModerate) OutlinedButton(onPressed: busy ? null : () async {
                await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => ModerationScreen(backend: widget.backend)));
                if (mounted) loadModerationAccess();
              }, child: const Text('Şikâyet inceleme')),
              const Text(
                'Engellenen kişiler',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (blocked.isEmpty && error == null)
                const Text('Engellediğin kimse yok.'),
              for (final person in blocked)
                Card(
                  child: ListTile(
                    title: Text(person.name),
                    trailing: TextButton(
                      onPressed: busy || loading ? null : () => unblock(person),
                      child: const Text('Engeli kaldır'),
                    ),
                  ),
                ),
              TextButton(
                onPressed: busy || loading ? null : load,
                child: const Text('Listeyi yenile'),
              ),
              const Divider(height: 48),
              const Text(
                'Hesabını sil',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hesabın, profilin, beğenilerin ve eşleşmelerin kalıcı olarak silinir. Bu işlem geri alınamaz.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: busy ? null : deleteAccount,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Hesabımı sil'),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.deleteAccount});
  final Future<void> Function(String password) deleteAccount;
  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.deleteAccount(password.text);
      password.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Hesabını kalıcı olarak sil?'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Onaylamak için şifreni gir ve aşağıya SİL yaz. Tüm eşleşmelerini kaybedeceksin.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Şifre'),
                validator:
                    (v) => v == null || v.isEmpty ? 'Şifreni gir.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                enabled: !busy,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Onay: SİL'),
                validator:
                    (v) =>
                        v?.trim() == 'SİL' ? null : 'Onaylamak için SİL yaz.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(busy ? 'Siliniyor…' : 'Kalıcı olarak sil'),
        ),
      ],
    ),
  );
}
