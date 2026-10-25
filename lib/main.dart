import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend/repository.dart';
import 'demo_app.dart' show PlayMatchApp;
import 'features/auth_panel.dart';
import 'features/member_home.dart';
import 'features/password_recovery.dart';

const authCallback = 'com.erdeminsan.playmatch://auth-callback';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (const bool.fromEnvironment('DEMO_MODE')) {
    runApp(const PlayMatchApp());
    return;
  }
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(
      const StartupMessage(
        'Bağlantı ayarları eksik. Uygulamayı config/development.json ile başlat.',
      ),
    );
    return;
  }
  try {
    await Supabase.initialize(url: url, anonKey: key);
    runApp(ConnectedApp(client: Supabase.instance.client));
  } catch (_) {
    runApp(
      const StartupMessage(
        'Uygulama başlatılamadı. Bağlantı ayarlarını kontrol edip yeniden aç.',
      ),
    );
  }
}

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF19182D),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFB8A2FF),
    brightness: Brightness.dark,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
  ),
);

class StartupMessage extends StatelessWidget {
  const StartupMessage(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: appTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(message)),
      ),
    ),
  );
}

class ConnectedApp extends StatelessWidget {
  const ConnectedApp({super.key, required this.client});
  final SupabaseClient client;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PlayMatch',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    home: SessionGate(client: client),
  );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, required this.client});
  final SupabaseClient client;
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final Stream<AuthState> authChanges;
  bool recovering = false;
  @override
  void initState() {
    super.initState();
    authChanges = widget.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: authChanges,
    builder: (context, snapshot) {
      final event = snapshot.data?.event;
      if (event == AuthChangeEvent.passwordRecovery) recovering = true;
      if (event == AuthChangeEvent.signedOut) recovering = false;
      final session = widget.client.auth.currentSession;
      if (recovering && session != null) {
        return PasswordRecovery(
          save: (password) async {
            await widget.client.auth.updateUser(
              UserAttributes(password: password),
            );
          },
          finish: () => widget.client.auth.signOut(scope: SignOutScope.global),
        );
      }
      if (session != null)
        return MemberHome(
          key: ValueKey(session.user.id),
          backend: Backend(widget.client),
        );
      return AuthPanel(
        authenticate: (email, password, signup) async {
          if (signup) {
            final result = await widget.client.auth.signUp(
              email: email,
              password: password,
              emailRedirectTo: authCallback,
            );
            return result.session == null
                ? 'E-postandaki doğrulama bağlantısını aç; sonra bu ekrandan giriş yap.'
                : null;
          }
          await widget.client.auth.signInWithPassword(
            email: email,
            password: password,
          );
          return null;
        },
        resetPassword:
            (email) => widget.client.auth.resetPasswordForEmail(
              email,
              redirectTo: authCallback,
            ),
        resend: (email) async {
          await widget.client.auth.resend(
            type: OtpType.signup,
            email: email,
            emailRedirectTo: authCallback,
          );
        },
      );
    },
  );
}
