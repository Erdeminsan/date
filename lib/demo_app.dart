import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'game/flight_game.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PlayMatchApp());
}

const ink = Color(0xFF19182D);
const lavender = Color(0xFFB8A2FF);

class PlayMatchApp extends StatelessWidget {
  const PlayMatchApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PlayMatch',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lavender,
        brightness: Brightness.dark,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          backgroundColor: lavender,
          foregroundColor: ink,
        ),
      ),
    ),
    home: const Home(),
  );
}

class DemoProfile {
  DemoProfile(this.name, this.city, this.interests, this.icon, this.color);
  final String name, city, interests;
  final IconData icon;
  final Color color;
  int unlocked = 0;
  bool matched = false;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final name = TextEditingController();
  final profiles = [
    DemoProfile(
      'Deniz',
      'İstanbul',
      'Tenis · Kahve · Canlı müzik',
      Icons.waves,
      const Color(0xFF90D9CC),
    ),
    DemoProfile(
      'Ece',
      'İzmir',
      'Fotoğraf · Seyahat · Sinema',
      Icons.wb_sunny_outlined,
      const Color(0xFFFFB49C),
    ),
    DemoProfile(
      'Aras',
      'Ankara',
      'Oyun · Kitap · Kamp',
      Icons.nightlight_round,
      lavender,
    ),
  ];
  bool entered = false, adult = false;
  int tab = 0, index = 0;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'playmatch',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Chip(label: Text('DEMO · 0.1')),
        ),
      ],
    ),
    body: SafeArea(child: entered ? mainBody() : onboarding()),
    bottomNavigationBar:
        entered
            ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (value) => setState(() => tab = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  label: 'Keşfet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sports_esports_outlined),
                  label: 'Eşleşmeler',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profil',
                ),
              ],
            )
            : null,
  );
  Widget onboarding() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 25),
      const Icon(Icons.sports_esports_rounded, size: 92, color: lavender),
      const SizedBox(height: 32),
      const Text(
        'Önce oyna.\nSonra tanış.',
        style: TextStyle(
          fontSize: 44,
          height: 1.06,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Bir dokunuş, küçük bir rekabet, yeni bir hikâye.',
        style: TextStyle(fontSize: 18, color: Colors.white70),
      ),
      const SizedBox(height: 32),
      TextField(
        controller: name,
        maxLength: 30,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Sana nasıl hitap edelim?',
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: adult,
        onChanged: (v) => setState(() => adult = v ?? false),
        title: const Text('18 yaşında veya daha büyüğüm.'),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty || !adult) {
            message('İsmini gir ve yaş koşulunu onayla.');
            return;
          }
          setState(() => entered = true);
        },
        child: const Text('Demoyu keşfet'),
      ),
      const SizedBox(height: 20),
      const Text(
        'Bu sürüm çevrimdışı bir prototiptir. Tüm kişiler ve eşleşmeler kurgusaldır. Bilgiler yalnızca bu oturumda tutulur; sunucuya gönderilmez.',
        style: TextStyle(color: Colors.white60),
      ),
    ],
  );
  Widget mainBody() {
    if (tab == 2)
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(
            radius: 42,
            child: Icon(Icons.person_outline, size: 44),
          ),
          const SizedBox(height: 20),
          Text(
            name.text.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(height: 24),
          const ListTile(
            title: Text('Prototip hesabı'),
            subtitle: Text('Gerçek kayıt ve giriş henüz bağlı değil.'),
          ),
          const ListTile(
            title: Text('Veri ve gizlilik'),
            subtitle: Text(
              'Fotoğraf, konum ve kişi listesi izni istenmez. Veriler uygulama kapanınca sıfırlanır.',
            ),
          ),
          OutlinedButton(
            onPressed:
                () => setState(() {
                  entered = false;
                  adult = false;
                  tab = 0;
                  index = 0;
                  name.clear();
                  for (final p in profiles) {
                    p.unlocked = 0;
                    p.matched = false;
                  }
                }),
            child: const Text('Demo verilerini sıfırla'),
          ),
        ],
      );
    if (tab == 1) {
      final matches = profiles.where((p) => p.matched).toList();
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Birlikte bir tur?',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text('Demo rakiple uç; kazandıkça yeni bir bilgi aç.'),
          const SizedBox(height: 24),
          if (matches.isEmpty)
            const Text(
              'Henüz eşleşme yok. Keşfet sekmesinden bir demo profilini beğen.',
            ),
          for (final p in matches)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.name} · Demo',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: p.unlocked / 3),
                    const SizedBox(height: 12),
                    Text(p.unlocked >= 1 ? 'Şehir: ${p.city}' : '🔒 Şehir'),
                    Text(p.unlocked >= 2 ? p.interests : '🔒 İlgi alanları'),
                    Text(
                      p.unlocked >= 3
                          ? 'Sohbet önizlemesi açıldı'
                          : '🔒 Sohbet önizlemesi',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => play(p),
                      child: const Text('Sky Hop oyna'),
                    ),
                    if (p.unlocked >= 3)
                      TextButton(
                        onPressed:
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ChatPreview(name: p.name),
                              ),
                            ),
                        child: const Text('Sohbeti keşfet'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    final p = profiles[index];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Merhaba, ${name.text.trim()} 👋',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        const Text(
          'Merakla başlar.',
          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('Birini tanımanın en eğlenceli yolu.'),
        const SizedBox(height: 26),
        Container(
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              colors: [p.color, const Color(0xFF34304B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(p.icon, size: 90, color: ink),
              const SizedBox(height: 24),
              Text(
                p.name,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text('Kurgusal profil · 18+'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '🔒 Şehir ve ilgi alanları oyunla açılır.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    () => setState(() => index = (index + 1) % profiles.length),
                child: const Text('Sonraki'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  setState(() {
                    p.matched = true;
                    tab = 1;
                  });
                  message(
                    'Demo eşleşmesi oluşturuldu. Gerçek kişiye beğeni gönderilmedi.',
                  );
                },
                child: const Text('♡ Beğen'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> play(DemoProfile p) async {
    final score = await Navigator.of(
      context,
    ).push<int>(MaterialPageRoute(builder: (_) => const GameScreen()));
    if (!mounted || score == null) return;
    const target = 3;
    final won = score >= target;
    setState(() {
      if (won && p.unlocked < 3) p.unlocked++;
    });
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(won ? 'Yeni bir kapı açıldı ✨' : 'Bir tur daha?'),
            content: Text(
              'Sen: $score · Demo hedefi: $target\n\n${won ? 'Beraberlik veya galibiyet: bilgi seviyesi ${p.unlocked}/3.' : 'Hedefe ulaşarak bir sonraki bilgiyi açabilirsin.'}\n\nBu skor gerçek bir rakibe ait değildir.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Devam'),
              ),
            ],
          ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final FlightGame game;
  bool suspended = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    game = FlightGame(
      onFinished:
          (score) => WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context, score);
          }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      game.pauseEngine();
      if (mounted) setState(() => suspended = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    game.pauseEngine();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sky Hop · Demo antrenmanı')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('45 saniye · Hedef: 3 puan · Uçmak için dokun'),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => game.flap(),
                    child: ClipRect(child: GameWidget(game: game)),
                  ),
                ),
                if (suspended)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: FilledButton(
                          onPressed: () {
                            setState(() => suspended = false);
                            game.resumeEngine();
                          },
                          child: const Text('Devam et'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Engelleri geç, puan topla. Çarparsan yeniden uç.'),
          ),
        ],
      ),
    ),
  );
}

class ChatPreview extends StatefulWidget {
  const ChatPreview({super.key, required this.name});
  final String name;
  @override
  State<ChatPreview> createState() => _ChatPreviewState();
}

class _ChatPreviewState extends State<ChatPreview> {
  final input = TextEditingController();
  final messages = <String>[];
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.name} · Sohbet önizlemesi')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Mesajlar yalnızca bu ekranda görünür. Kimseye gönderilmez; ekran kapanınca silinir.',
            ),
          ),
          Expanded(
            child: ListView(
              children:
                  messages
                      .map(
                        (m) => Align(
                          alignment: Alignment.centerRight,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(m),
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Bir merhaba yaz…',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Yerel önizlemeye ekle',
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    if (input.text.trim().isEmpty) return;
                    setState(() {
                      messages.add(input.text.trim());
                      input.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
