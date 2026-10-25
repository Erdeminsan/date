import 'package:flutter/material.dart';
import '../backend/repository.dart';
import '../demo_app.dart' show GameScreen;
import 'profile_editor.dart';

class MemberHome extends StatefulWidget {
  const MemberHome({super.key, required this.backend});
  final Backend backend;
  @override
  State<MemberHome> createState() => _MemberHomeState();
}

class _MemberHomeState extends State<MemberHome> {
  OwnProfile? profile;
  List<Person> people = [];
  List<Connection> connections = [];
  bool loading = true, acting = false;
  String? error;
  int tab = 0;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await widget.backend.profile();
      final candidates =
          p == null ? <Person>[] : await widget.backend.discover();
      final matches =
          p == null ? <Connection>[] : await widget.backend.matches();
      if (!mounted || request != generation) return;
      setState(() {
        profile = p;
        people = candidates;
        connections = matches;
      });
    } catch (e) {
      if (mounted && request == generation)
        setState(() => error = friendlyError(e));
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  void notify(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> act(Future<void> Function() action) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      await action();
      await reload();
    } catch (e) {
      notify(friendlyError(e));
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> block(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Profili engelle?'),
            content: const Text(
              'Birbirinizi keşfette göremezsiniz. Mevcut eşleşme ve karşılıklı beğeniler kaldırılır.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Engelle'),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) await act(() => widget.backend.block(id));
  }

  Future<void> report(String id) async {
    var input = "";
    final reason = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Profili şikâyet et'),
            content: TextField(
              onChanged: (value) => input = value,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Nedenini yaz (en az 5 karakter)',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () {
                  if (input.trim().length >= 5)
                    Navigator.pop(context, input.trim());
                },
                child: const Text('Gönder'),
              ),
            ],
          ),
    );
    if (reason != null && mounted)
      await act(() async {
        await widget.backend.report(id, reason);
        notify('Şikâyetin kaydedildi.');
      });
  }

  Widget menu(String id) => PopupMenuButton<String>(
    enabled: !acting,
    onSelected: (v) {
      if (v == 'block') {
        block(id);
      } else {
        report(id);
      }
    },
    itemBuilder:
        (_) => const [
          PopupMenuItem(value: 'block', child: Text('Engelle')),
          PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
        ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('playmatch'),
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: loading || acting ? null : reload,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Çıkış yap',
          onPressed:
              acting
                  ? null
                  : () async {
                    try {
                      await widget.backend.client.auth.signOut();
                    } catch (e) {
                      notify(friendlyError(e));
                    }
                  },
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: SafeArea(child: body()),
    bottomNavigationBar:
        profile == null
            ? null
            : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected:
                  acting ? null : (v) => setState(() => tab = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  label: 'Keşfet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_outline),
                  label: 'Eşleşmeler',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profil',
                ),
              ],
            ),
  );
  Widget body() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!),
              const SizedBox(height: 16),
              FilledButton(onPressed: reload, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    if (profile == null || tab == 2)
      return ProfileEditor(
        key: ValueKey(profile?.person.id ?? 'new'),
        backend: widget.backend,
        initial: profile,
        onSaved: () {
          notify('Profil kaydedildi.');
          reload();
        },
      );
    if (tab == 1)
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Birbirinizi beğendiniz.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (connections.isEmpty)
              const Text(
                'Henüz eşleşme yok. Karşılıklı beğeniler burada görünür.',
              ),
            for (final c in connections)
              Card(
                child: ListTile(
                  title: Text(c.name),
                  subtitle: const Text(
                    'Eşleşme kaydedildi · Oyun daveti yakında',
                  ),
                  trailing: menu(c.otherId),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Sky Hop antrenmanı',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tek başına pratik yap. Bu tur başka kullanıcının profil bilgisini açmaz.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final score = await Navigator.of(context).push<int>(
                  MaterialPageRoute(builder: (_) => const GameScreen()),
                );
                if (mounted && score != null)
                  notify(
                    'Antrenman skorun: $score. Profil kilitleri değişmedi.',
                  );
              },
              child: const Text('Antrenmana başla'),
            ),
          ],
        ),
      );
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Merhaba, ${profile!.person.name}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          const Text(
            'Merakla başlar.',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          if (!profile!.person.visible)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Profilin gizli. Beğeni göndermek için Profil sekmesinden görünürlüğünü aç.',
                ),
              ),
            ),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Şimdilik yeni profil yok. İkinci bir gerçek test hesabı oluşturduğunda burada görünebilir.',
              ),
            ),
          for (final p in people)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.person_outline)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        menu(p.id),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('🔒 Şehir ve ilgi alanları kilitli'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed:
                          acting || !profile!.person.visible
                              ? null
                              : () => act(() async {
                                final matched = await widget.backend.like(p.id);
                                notify(
                                  matched
                                      ? 'Eşleştiniz! Eşleşmeler sekmesine göz at.'
                                      : 'Beğenin kaydedildi.',
                                );
                              }),
                      child: const Text('♡ Beğen'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
