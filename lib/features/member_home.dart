import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/repository.dart';
import '../demo_app.dart' show GameScreen;
import 'profile_editor.dart';
import 'account_settings.dart';
import 'profile_photo.dart';
import 'photo_report_screen.dart';
import 'profile_report_dialog.dart';
import 'game_lobby.dart';
import 'match_details_screen.dart';
import 'chat_screen.dart';
import 'discovery_preferences_screen.dart';

class MemberHome extends StatefulWidget {
  const MemberHome({super.key, required this.backend});
  final Backend backend;
  @override
  State<MemberHome> createState() => _MemberHomeState();
}

class _MemberHomeState extends State<MemberHome> with WidgetsBindingObserver {
  Timer? matchTimer;
  late final String owner;
  bool foreground = true, syncingMatches = false;
  String? matchesError;
  OwnProfile? profile;
  List<Person> people = [];
  List<Connection> connections = [];
  bool loading = true, acting = false, loadingMore = false;
  FeedCursor? peopleCursor, matchesCursor;
  String? error;
  int tab = 0;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    owner = widget.backend.userId;
    WidgetsBinding.instance.addObserver(this);
    reload();
    matchTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshMatches());
  }

  @override
  void dispose() {
    generation++; matchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this); super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      generation++;
      setState(() {
        syncingMatches = false; loadingMore = false; loading = false;
        connections = []; matchesCursor = null;
      });
    } else if (profile == null) {
      reload();
    } else {
      refreshMatches();
    }
  }
  void checkOwner() {
    if (widget.backend.userId != owner) throw StateError('Session changed');
  }
  Future<void> refreshMatches() async {
    if (!mounted || !foreground || tab != 1 || profile == null || loading ||
        loadingMore || acting || syncingMatches || ModalRoute.of(context)?.isCurrent != true) return;
    final request = generation;
    final pages = connections.isEmpty ? 1 : (connections.length + 19) ~/ 20;
    syncingMatches = true;
    try {
      checkOwner();
      final items = <String, Connection>{};
      FeedCursor? cursor;
      for (var pageNumber = 0; pageNumber < pages; pageNumber++) {
        final page = await widget.backend.matches(before: cursor).timeout(const Duration(seconds: 6));
        if (!mounted || request != generation || !foreground || tab != 1 || ModalRoute.of(context)?.isCurrent != true) return;
        checkOwner();
        for (final item in page.items) { items[item.id] = item; }
        cursor = page.next;
        if (cursor == null) break;
      }
      setState(() { connections = items.values.toList(); matchesCursor = cursor; matchesError = null; });
    } catch (_) {
      if (mounted && request == generation) setState(() {
        connections = []; matchesCursor = null;
        matchesError = 'Eşleşmeler güncellenemedi. Bağlantı sağlandığında yeniden denenecek.';
      });
    } finally {
      if (mounted && request == generation) setState(() => syncingMatches = false);
    }
  }

  Future<void> reload() async {
    final request = ++generation;
    setState(() {
      loading = true;
      syncingMatches = false; matchesError = null;
      loadingMore = false;
      error = null;
    });
    try {
      checkOwner();
      final p = await widget.backend.profile();
      checkOwner();
      final candidates =
          p == null ? const FeedPage<Person>([], null) : await widget.backend.discover();
      checkOwner();
      final matches =
          p == null ? const FeedPage<Connection>([], null) : await widget.backend.matches();
      if (!mounted || request != generation) return;
      checkOwner();
      setState(() {
        profile = p;
        people = candidates.items;
        connections = matches.items;
        peopleCursor = candidates.next;
        matchesCursor = matches.next;
      });
    } catch (e) {
      if (mounted && request == generation)
        setState(() => error = friendlyError(e));
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> loadMore(bool matching) async {
    final cursor = matching ? matchesCursor : peopleCursor;
    if (cursor == null || loading || loadingMore || acting || syncingMatches) return;
    final request = generation;
    setState(() => loadingMore = true);
    try {
      checkOwner();
      if (matching) {
        final page = await widget.backend.matches(before: cursor);
        if (!mounted || request != generation) return;
        checkOwner();
        setState(() {
          connections = {for (final item in [...connections, ...page.items]) item.id: item}.values.toList();
          matchesCursor = page.next;
        });
      } else {
        final page = await widget.backend.discover(before: cursor);
        if (!mounted || request != generation) return;
        checkOwner();
        setState(() {
          people = {for (final item in [...people, ...page.items]) item.id: item}.values.toList();
          peopleCursor = page.next;
        });
      }
    } catch (e) {
      if (mounted && request == generation) notify(friendlyError(e));
    } finally {
      if (mounted && request == generation) setState(() => loadingMore = false);
    }
  }

  Widget pageFooter(bool matching) {
    final cursor = matching ? matchesCursor : peopleCursor;
    if (cursor == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: OutlinedButton(
        onPressed: loadingMore || acting || syncingMatches ? null : () => loadMore(matching),
        child: Text(loadingMore ? 'Yükleniyor…' : matching ? 'Daha fazla eşleşme' : 'Daha fazla profil'),
      ),
    );
  }

  void notify(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> act(Future<void> Function() action) async {
    if (acting) return;
    generation++;
    setState(() { acting = true; syncingMatches = false; loadingMore = false; });
    try {
      checkOwner();
      await action();
      await reload();
    } catch (e) {
      notify(friendlyError(e));
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> block(String id) async {
    final confirmed = await showDialog<bool>(useRootNavigator: false,
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Profili engelle?'),
            content: const Text(
              'Birbirinizi keşfette göremezsiniz. Mevcut eşleşme ve karşılıklı beğeniler kaldırılır.',
            ),
            actions: [
        if (profile != null && tab == 0) IconButton(tooltip: 'Keşfet tercihleri',icon: const Icon(Icons.tune),
          onPressed: acting || loading ? null : () async {
            final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => DiscoveryPreferencesScreen(backend: widget.backend)));
            if (mounted && saved == true) await reload();
          }),
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
    final saved = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) => ProfileReportDialog(backend: widget.backend, targetId: id),
    );
    if (saved == true && mounted) notify('Şikâyetin kaydedildi.');
  }

  Future<void> unmatch(Connection connection) async {
    final confirmed = await showDialog<bool>(useRootNavigator: false, context: context, builder: (context) => AlertDialog(
      title: Text('${connection.name} ile eşleşmeden ayrıl?'),
      content: const Text('Eşleşme, karşılıklı beğeniler ve oyun davetleri silinir. Yeniden eşleşmek için ikinizin de tekrar beğenmesi gerekir. Birbirinizi keşfette görebilirsiniz; bunu istemiyorsan Engelle seçeneğini kullan.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eşleşmeden ayrıl')),
      ],
    ));
    if (confirmed == true && mounted) await act(() async {
      await widget.backend.unmatch(connection.id);
      notify('Eşleşme kaldırıldı.');
    });
  }

  Widget menu(String id, {Connection? connection,String? photoPath}) => PopupMenuButton<String>(
    enabled: !acting,
    onSelected: (v) {
      if(v=='photo' && photoPath!=null){
        Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>PhotoReportScreen(backend:widget.backend,targetId:id,path:photoPath))).then((saved){
          if(mounted){if(saved==true)notify('Fotoğraf şikâyetin kaydedildi.');reload();}
        });
      } else if (v == 'block') {
        block(id);
      } else if (v == 'details' && connection != null) {
        Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => MatchDetailsScreen(backend: widget.backend, connection: connection)));
      } else if (v == 'game' && connection != null) {
        Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => GameLobby(backend: widget.backend, connection: connection)));
      } else if (v == 'unmatch' && connection != null) {
        unmatch(connection);
      } else {
        report(id);
      }
    },
    itemBuilder:
        (_) => [
          if (connection != null) const PopupMenuItem(value: 'details', child: Text('Açılan bilgiler')),
          if (connection != null) const PopupMenuItem(value: 'game', child: Text('Oyun daveti')),
          if (connection != null) const PopupMenuItem(value: 'unmatch', child: Text('Eşleşmeden ayrıl')),
          const PopupMenuItem(value: 'block', child: Text('Engelle')),
          const PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
          if(photoPath!=null)const PopupMenuItem(value:'photo',child:Text('Fotoğrafı şikâyet et')),
        ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('playmatch'),
      actions: [
        IconButton(
          tooltip: 'Hesap ayarları',
          icon: const Icon(Icons.settings_outlined),
          onPressed:
              acting
                  ? null
                  : () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder:
                            (_) => AccountSettings(backend: widget.backend),
                      ),
                    );
                    if (mounted &&
                        widget.backend.client.auth.currentSession != null)
                      await reload();
                  },
        ),
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
                  acting ? null : (v) { setState(() => tab = v); if (v == 1) refreshMatches(); },
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
            if (matchesError != null) Text(matchesError!),
            if (connections.isEmpty && matchesError == null)
              const Text(
                'Henüz eşleşme yok. Karşılıklı beğeniler burada görünür.',
              ),
            for (final c in connections)
              Card(
                child: ListTile(
                  leading: ProfilePhoto(backend: widget.backend, path: c.photoPath),
                  title: Text(c.name),
                  onTap: acting ? null : () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => ChatScreen(backend: widget.backend, connection: c)),
                  ),
                  subtitle: const Text(
                    'Sohbeti aç',
                  ),
                  trailing: menu(c.otherId, connection: c, photoPath:c.photoPath),
                ),
              ),
            pageFooter(true),
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
                        ProfilePhoto(backend: widget.backend, path: p.photoPath),
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
                        menu(p.id,photoPath:p.photoPath),
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
          pageFooter(false),
        ],
      ),
    );
  }
}
