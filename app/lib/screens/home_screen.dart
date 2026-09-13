import 'dart:async';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import 'home_shell.dart';

/// 🏠 Dashboard: kartu profil singkat, build yang lagi jalan (LIVE, poll 4 dtk),
/// APK siap download, info TTL. Semua data dari REST API bot — native semua.
class HomeScreen extends StatefulWidget {
  final void Function(BuildContext) onOpenTop;
  const HomeScreen({super.key, required this.onOpenTop});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _me;
  Map<String, dynamic>? _job;
  int _files = 0;
  Timer? _timer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _pollJob());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    await Future.wait([_loadMe(), _pollJob(), _loadFiles()]);
  }

  Future<void> _loadMe() async {
    try {
      final me = await DzrApi.I.me();
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _loadFiles() async {
    try {
      final f = await DzrApi.I.files();
      final items = asListOfMaps(f['items']);
      if (!mounted) return;
      setState(() => _files = items.length);
    } catch (_) {}
  }

  Future<void> _pollJob() async {
    try {
      final j = await DzrApi.I.job();
      if (!mounted) return;
      setState(() => _job = (j['job'] == null) ? null : Map<String, dynamic>.from(j['job'] as Map));
    } catch (_) {}
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await DzrApi.I.cancelJob();
      if (!mounted) return;
      _toast('Build dibatalkan.');
      await _pollJob();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Gagal cancel — coba lagi.');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _statusText(Map<String, dynamic> job) {
    final st = (job['status'] ?? '') as String;
    final gh = job['gh'] is Map ? Map<String, dynamic>.from(job['gh'] as Map) : null;
    switch (st) {
      case 'uploading':
        return gh == null ? 'Upload ZIP ke server build…' : 'Antrian build…';
      case 'building':
        final step = job['step'];
        if (step is String && step.isNotEmpty) return 'Compile: $step';
        return gh?['status'] == 'completed' ? 'Ngerampungin…' : 'Compile jalan…';
      default:
        return st.isEmpty ? 'Proses…' : st;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(
            gradient: DzrTheme.iconGradient(), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          const Text('DZR Builder'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 90),
          children: [
            // ── Kartu profil ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: DzrTheme.heroGradient(),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: me == null
                  ? const LinearProgressIndicator(minHeight: 2)
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(shortName(me['name'] as String?),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: DzrTheme.seed.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('${me['role'] ?? 'Member'}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text('${me['title'] ?? ''}',
                          style: TextStyle(color: DzrTheme.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 14),
                      Row(children: [
                        _stat('🎫 Credit', me['unlimited'] == true ? '∞' : '${me['credits'] ?? 0}'),
                        _stat('✅ Sukses', '${me['succ'] ?? 0}'),
                        _stat('🔥 Minggu ini', '${me['weekN'] ?? 0}'),
                        _stat('📦 Max ZIP', '${me['capMB'] ?? '?'} MB'),
                      ]),
                    ]),
            ),
            const SizedBox(height: 8),

            // ── Build yang lagi jalan (LIVE) ──
            if (_job != null) _activeJobCard(_job!) else _idleCard(),

            // ── APK siap download ──
            Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: DzrTheme.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.download_rounded, color: DzrTheme.accent),
                ),
                title: Text('APK siap download ($_files)', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_files > 0
                    ? 'Ada hasil build lu di tab Riwayat — auto-hapus 5 jam.'
                    : 'Belum ada file. Hasil build bakal nongol di sini.',
                  style: const TextStyle(fontSize: 12.5)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {},
              ),
            ),

            // ── Info TTL + tombol leaderboard ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.timer_outlined, color: DzrTheme.warn),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    'APK hasil build auto-kehapus 5 jam (semua level) — download & simpen sekarang ya.',
                    style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12.5, height: 1.5),
                  )),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => widget.onOpenTop(context),
                icon: const Icon(Icons.emoji_events_rounded, color: DzrTheme.warn),
                label: const Text('Lihat Leaderboard Builder'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String val) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11)),
      const SizedBox(height: 3),
      Text(val, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    ]),
  );

  Widget _idleCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Icon(Icons.nightlight_round, color: Colors.white.withOpacity(0.35)),
        const SizedBox(width: 12),
        Expanded(child: Text(
          'Gak ada build yang jalan. Gas bikin APK baru di tab Build!',
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
        )),
      ]),
    ),
  );

  Widget _activeJobCard(Map<String, dynamic> job) {
    final building = (job['status'] == 'building');
    final gh = job['gh'] is Map ? Map<String, dynamic>.from(job['gh'] as Map) : null;
    final pct = building ? 0.55 : 0.18;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: DzrTheme.seed.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
              child: const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: DzrTheme.seed),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(
              '🔨 Build Lagi Jalan',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            )),
            TextButton(
              onPressed: _cancelling ? null : _cancel,
              child: _cancelling
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Cancel', style: TextStyle(color: DzrTheme.bad)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(shortName('${job['fileName'] ?? 'project.zip'}', 34),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_statusText(job),
              style: TextStyle(color: DzrTheme.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct, minHeight: 7,
                backgroundColor: Colors.white.withOpacity(0.08), color: DzrTheme.seed),
          ),
          const SizedBox(height: 10),
          Text(
            '${job['type'] == 'kotlin' ? '🤖 Kotlin' : '🐦 Flutter'} · ${job['buildType'] == 'debug' ? '🐞 Debug' : '🚀 Release'}'
            '${gh?['runNumber'] != null ? ' · run #${gh!['runNumber']}' : ''} · progress juga live di chat bot',
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11.5),
          ),
        ]),
      ),
    );
  }
}
