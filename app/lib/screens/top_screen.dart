import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';

/// 🏆 Leaderboard — 7 hari + all-time, gelar builder, tanda "← lu".
class TopScreen extends StatefulWidget {
  const TopScreen({super.key});

  @override
  State<TopScreen> createState() => _TopScreenState();
}

class _TopScreenState extends State<TopScreen> {
  List<Map<String, dynamic>>? _weekly;
  List<Map<String, dynamic>>? _allTime;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _err = false; });
    try {
      final t = await DzrApi.I.top();
      if (!mounted) return;
      setState(() {
        _weekly = asListOfMaps(t['weekly']);
        _allTime = asListOfMaps(t['allTime']);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = true);
    }
  }

  String _medal(int i) => ['🥇', '🥈', '🥉'][i];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Leaderboard Builder')),
      body: _err
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Gagal load leaderboard.'),
              TextButton(onPressed: _load, child: const Text('Coba lagi')),
            ]))
          : (_weekly == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 30),
                  children: [
                    _section('📅 7 Hari Terakhir', _weekly!, withTitle: false),
                    _section('♾️ All Time', _allTime!, withTitle: true),
                  ],
                )),
    );
  }

  Widget _section(String title, List<Map<String, dynamic>> list, {required bool withTitle}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text('Masih sepi — jadi builder pertama! 🚀',
              style: TextStyle(color: Colors.white.withOpacity(0.45))),
        )
      else
        ...list.asMap().entries.map((e) {
          final i = e.key;
          final u = e.value;
          final me = u['me'] == true;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: me ? DzrTheme.seed.withOpacity(0.18) : DzrTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: me ? Border.all(color: DzrTheme.seed) : Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(children: [
              SizedBox(width: 34, child: Text(i < 3 ? _medal(i) : '${i + 1}.',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(shortName('${u['name']}', 18),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800))),
                  if (me) ...[
                    const SizedBox(width: 6),
                    const Text('← lu', style: TextStyle(color: DzrTheme.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ]),
                if (withTitle)
                  Text('${u['title'] ?? ''}',
                      style: TextStyle(color: DzrTheme.accent.withOpacity(0.85), fontSize: 10.5)),
              ])),
              Text('${u['n']}x', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ]),
          );
        }),
    ]);
  }
}
