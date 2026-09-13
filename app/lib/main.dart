import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const DzrApp());
}

class DzrApp extends StatelessWidget {
  const DzrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DZR Builder',
      debugShowCheckedModeBanner: false,
      theme: DzrTheme.dark(),
      home: const AuthGate(),
    );
  }
}

/// Gerbang login: kalau key udah tersimpan → langsung ke shell utama.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  String? _key;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final url = sp.getString('dzr_base_url') ?? DzrApi.defaultBaseUrl;
      final key = sp.getString('dzr_key');
      DzrApi.I.configure(baseUrl: url, key: key);
      if (!mounted) return;
      setState(() {
        _key = key;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return (_key != null && _key!.isNotEmpty)
        ? const HomeShell()
        : const LoginScreen();
  }
}

/// Simpan sesi + terusin signal logout antar layar.
class Session {
  static Future<void> save(String url, String key) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('dzr_base_url', url);
    await sp.setString('dzr_key', key);
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('dzr_key');
  }
}
