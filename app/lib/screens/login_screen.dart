import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../main.dart';
import 'home_shell.dart';

/// 🔑 Layar login — tempel key dari /getappkey (bot Telegram).
/// Gak ada webview sama sekali — murni form native.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController(text: DzrApi.defaultBaseUrl);
  bool _busy = false;
  bool _showUrl = false;
  Map<String, dynamic>? _info;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await DzrApi.I.info();
      if (!mounted) return;
      setState(() => _info = info);
    } catch (_) {/* offline — UI tetap jalan */}
  }

  Future<void> _login() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      _toast('Tempel key-nya dulu — /getappkey ke bot ya.');
      return;
    }
    setState(() => _busy = true);
    try {
      DzrApi.I.configure(baseUrl: _urlCtrl.text.trim(), key: key);
      await DzrApi.I.me(); // validasi key
      await Session.save(_urlCtrl.text.trim(), key);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Gak bisa nyambung ke server. Cek internet / URL server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final botUsername = (_info?['botUsername'] as String?) ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: DzrTheme.iconGradient(),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 54),
                ),
                const SizedBox(height: 20),
                const Text(
                  'DZR Builder',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
                const SizedBox(height: 6),
                Text(
                  'Versi APK dari bot — build APK langsung dari HP lu.\n100% native, tanpa WebView.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.5),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _keyCtrl,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'Tempel key lu (dzr-…)',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null && data!.text!.isNotEmpty) {
                          _keyCtrl.text = data.text!.trim();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_showUrl) ...[
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      hintText: 'URL server (http://…:3000)',
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login_rounded),
                  label: Text(_busy ? 'Ngecek key…' : 'Masuk'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showUrl = !_showUrl),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(_showUrl ? 'Sembunyikan opsi server' : 'Opsi server'),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: DzrTheme.card,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🔑 Belum punya key?', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        '1. Buka bot${botUsername.isNotEmpty ? ' @$botUsername' : ''} di Telegram\n'
                        '2. Kirim /getappkey\n'
                        '3. Salin key → tempel di atas',
                        style: TextStyle(color: Colors.white.withOpacity(0.65), height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _info != null
                      ? '${_info!['bot'] ?? 'DZR CloudBuilder'} v${_info!['botVersion'] ?? '?'} · App v${_info!['version'] ?? '1.0.0'}'
                      : 'Nyambungin ke server…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
