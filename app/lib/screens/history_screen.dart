import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import '../core/api.dart';
import '../core/theme.dart';

/// 🗂 Riwayat: build lu (20 terakhir) + APK yang masih bisa di-download
/// (TTL 5 jam — kedaluwarsa auto-hapus di server juga).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _hist = [];
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  String? _dlName;
  double _dlPct = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final h = await DzrApi.I.history();
      final f = await DzrApi.I.files();
      if (!mounted) return;
      setState(() {
        _hist = asListOfMaps(h['items']);
        _files = asListOfMaps(f['items']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('Gagal load: $e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _download(Map<String, dynamic> f) async {
    final name = '${f['name'] ?? 'app.apk'}';
    try {
      setState(() {
        _dlName = name;
        _dlPct = 0;
      });
      // 1. Download ke temp (native IO) dengan progress bar
      final tmp = '${Directory.systemTemp.path}/dzr_$name';
      await DzrApi.I.downloadFile(
        '/api/v1/builds/files/${Uri.encodeComponent(name)}/download',
        tmp,
        onProgress: (rec, total) {
          if (!mounted || total <= 0) return;
          setState(() => _dlPct = rec / total);
        },
      );
      final bytes = File(tmp).readAsBytesSync();
      try { File(tmp).deleteSync(); } catch (_) {}
      // 2. Sekali picker SAF — pilih lokasi + tulis sekaligus
      final saved = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
      if (!mounted) return;
      setState(() { _dlName = null; _dlPct = 0; });
      _toast(saved != null ? '✅ Tersimpan: $name' : 'Download dibatalin.');
    } catch (e) {
      if (!mounted) return;
      setState(() { _dlName = null; _dlPct = 0; });
      _toast('Download gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Build'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                children: [
                  // ── APK siap download ──
                  if (_files.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                      child: Text('📦 APK Siap Download', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    ..._files.map(_fileTile),
                  ],
                  // ── Riwayat ──
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Text('🔥 Build Lu (20 terakhir)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  if (_hist.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Belum ada build. Gas di tab Build! 🚀',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.45))),
                    )
                  else
                    ..._hist.map(_histTile),
                ],
              ),
            ),
    );
  }

  Widget _fileTile(Map<String, dynamic> f) {
    final exp = (f['expiresAt'] is num) ? (f['expiresAt'] as num).toInt() : null;
    final dl = _dlName == f['name'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.android_rounded, color: DzrTheme.good),
            const SizedBox(width: 10),
            Expanded(child: Text(shortName('${f['name']}', 26), style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(fmtMB(f['size']), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: dl ? null : () => _download(f),
              style: FilledButton.styleFrom(
                backgroundColor: DzrTheme.good,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: const Size(0, 36),
              ),
              child: Text(dl ? '…' : 'Download', style: const TextStyle(fontSize: 12.5)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('⏳ auto-hapus: ${fmtExpiry(exp)} · ${f['project'] ?? ''}',
              style: TextStyle(color: DzrTheme.warn.withOpacity(0.85), fontSize: 11.5)),
          if (dl) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _dlPct <= 0 ? null : _dlPct,
                minHeight: 6, color: DzrTheme.good, backgroundColor: Colors.white.withOpacity(0.08),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _histTile(Map<String, dynamic> h) {
    final ok = h['status'] == 'success';
    return Card(
      child: ListTile(
        leading: Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: ok ? DzrTheme.good : DzrTheme.bad),
        title: Text(shortName('${h['project'] ?? 'Project'}', 26),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${h['mode'] ?? '—'}${h['apkSize'] != null ? ' · 💾 ${h['apkSize']} MB' : ''}'
          '${h['duration'] != null ? ' · ⏱ ${fmtDurationSec(h['duration'])}' : ''}\n${fmtTimeAgo(h['at'] as String?)}',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11.5, height: 1.5),
        ),
        isThreeLine: true,
      ),
    );
  }
}
