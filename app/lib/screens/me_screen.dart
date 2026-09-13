import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../main.dart';
import 'login_screen.dart'; // LoginScreen buat logout
import 'top_screen.dart';

/// 👤 Profil: kartu builder lengkap + kelola key app + logout.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await DzrApi.I.me();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {}
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: DzrTheme.cardAlt,
        title: const Text('Logout?'),
        content: const Text('Key bakal dihapus dari app ini (key-nya sendiri tetap aktif di server — cabut permanen pakai /revokeappkey di bot).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
        ],
      ),
    );
    if (ok != true) return;
    await Session.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _copyKey() async {
    final k = DzrApi.I.key;
    if (k == null) return;
    await Clipboard.setData(ClipboardData(text: k));
    _toast('Key dicopy ke clipboard.');
  }

  String _maskKey(String? k) {
    if (k == null || k.length < 16) return '•••';
    return '${k.substring(0, 9)}••••••••${k.substring(k.length - 4)}';
  }

  String _initial(String name) {
    final v = name.trim();
    return v.isEmpty ? '?' : v.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final rate = ((me?['rate'] as num?) ?? 0).toDouble();
    final next = me?['nextMilestone'] is Map ? Map<String, dynamic>.from(me!['nextMilestone'] as Map) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Kartu Saya')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 30),
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: DzrTheme.heroGradient(),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: me == null
                  ? const LinearProgressIndicator(minHeight: 2)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: DzrTheme.seed,
                          child: Text(_initial('${me['name']}'),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(shortName('${me['name']}', 22), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                          Text('${me['role']} · ${me['title']}', style: const TextStyle(color: DzrTheme.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ])),
                      ]),
                      const SizedBox(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('🎫 Credit: ${me['unlimited'] == true ? '♾️ Unlimited' : '${me['credits']}'}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('📅 ${me['joined'] ?? '—'}', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
                      ]),
                      const SizedBox(height: 14),
                      Text('✅ ${me['succ']} sukses · ❌ ${me['failed']} gagal · 🔥 ${me['weekN']} minggu ini',
                          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5)),
                      const SizedBox(height: 8),
                      Text('🛠 Mode favorit: ${me['favMode'] ?? '—'}',
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
                    ]),
            ),
            const SizedBox(height: 8),
            if (next != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.flag_rounded, color: DzrTheme.warn),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      'Kurang ${next['remain']} build sukses lagi → bonus +${next['bonus']} credit!',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    )),
                  ]),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('🔑 Key App Lu', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_maskKey(DzrApi.I.key),
                      style: const TextStyle(fontFamily: 'monospace', color: DzrTheme.accent, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('Jangan share ke siapa pun — rotate kapan aja via /getappkey.',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: OutlinedButton.icon(
                onPressed: _copyKey,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Salin Key'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TopScreen()));
                },
                icon: const Icon(Icons.emoji_events_rounded, size: 18, color: DzrTheme.warn),
                label: const Text('Leaderboard'),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _logout,
                style: FilledButton.styleFrom(backgroundColor: DzrTheme.bad.withOpacity(0.85)),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
              ),
            ),
            const SizedBox(height: 14),
            Center(child: Text(
              'DZR Builder v1.0.0 · native, tanpa WebView',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
            )),
          ],
        ),
      ),
    );
  }
}
