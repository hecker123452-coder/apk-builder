import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import '../core/api.dart';
import '../core/theme.dart';

/// 🔨 Layar build: pilih ZIP → mode Flutter/Kotlin → Release/Debug → upload
/// (progress native) → pipeline bot jalan. Gak ada webview — file_picker SAF.
class BuildScreen extends StatefulWidget {
  final VoidCallback onSubmitted; // dipanggil abis submit → loncat ke Home
  const BuildScreen({super.key, required this.onSubmitted});

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  String _type = 'flutter';
  String _build = 'release';
  final _nameCtrl = TextEditingController();
  String? _zipPath;
  String? _zipName;
  int _zipSize = 0;
  double? _upPct;
  bool _busy = false;

  Future<void> _pickZip() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: false,
    );
    final f = res?.files.single;
    if (f == null || f.path == null) return;
    final size = File(f.path!).lengthSync();
    setState(() {
      _zipPath = f.path;
      _zipName = f.name;
      _zipSize = size;
    });
  }

  Future<void> _submit() async {
    if (_zipPath == null) {
      _toast('Pilih ZIP project lu dulu ya.');
      return;
    }
    setState(() {
      _busy = true;
      _upPct = 0;
    });
    try {
      final bytes = await File(_zipPath!).readAsBytes();
      await DzrApi.I.uploadZip(
        bytes: bytes,
        filename: _zipName ?? 'project.zip',
        type: _type,
        build: _build,
        appName: _nameCtrl.text,
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          setState(() => _upPct = sent / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _upPct = null;
        _zipPath = null;
        _zipName = null;
        _zipSize = 0;
      });
      await showDialog(context: context, builder: (_) => _doneDialog());
      widget.onSubmitted();
    } on ApiException catch (e) {
      setState(() { _busy = false; _upPct = null; });
      _toast(e.message);
    } catch (e) {
      setState(() { _busy = false; _upPct = null; });
      _toast('Upload gagal: $e');
    }
  }

  Widget _doneDialog() => AlertDialog(
    backgroundColor: DzrTheme.cardAlt,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    title: const Text('🚀 Build Dimulai!'),
    content: const Text(
      'ZIP lu udah masuk pipeline yang sama sama bot.\n\n'
      '• Progress LIVE → tab Home\n'
      '• APK jadi → notif di chat bot + bisa di-download ulang dari tab Riwayat',
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Oke'))],
  );

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Build APK')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Mode ──
          _section('🛠 Mode Build'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'flutter', icon: Icon(Icons.flutter_dash), label: Text('Flutter')),
              ButtonSegment(value: 'kotlin', icon: Icon(Icons.android), label: Text('Kotlin')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),

          // ── Tipe build ──
          _section('🔧 Tipe Build'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'release', icon: Icon(Icons.rocket_launch_rounded), label: Text('Release')),
              ButtonSegment(value: 'debug', icon: Icon(Icons.bug_report_rounded), label: Text('Debug')),
            ],
            selected: {_build},
            onSelectionChanged: (s) => setState(() => _build = s.first),
          ),
          const SizedBox(height: 16),

          // ── Nama app ──
          _section('📱 Nama App (opsional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 40,
            decoration: const InputDecoration(
              hintText: 'Kosongin = dari nama ZIP',
              counterText: '',
              prefixIcon: Icon(Icons.apps_rounded),
            ),
          ),
          const SizedBox(height: 16),

          // ── ZIP ──
          _section('📦 ZIP Project'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _busy ? null : _pickZip,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: DzrTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _zipPath == null ? Colors.white.withOpacity(0.1) : DzrTheme.seed,
                  width: _zipPath == null ? 1 : 1.5,
                ),
              ),
              child: _zipPath == null
                  ? Column(children: [
                      Icon(Icons.upload_file_rounded, size: 40, color: Colors.white.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      Text('Tap buat pilih file .zip', style: TextStyle(color: Colors.white.withOpacity(0.55))),
                      const SizedBox(height: 4),
                      Text('Zip folder project lu (harus ada ${_type == 'kotlin' ? 'build.gradle' : 'pubspec.yaml'})',
                          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11.5)),
                    ])
                  : Row(children: [
                      const Icon(Icons.folder_zip_rounded, color: DzrTheme.accent, size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(shortName(_zipName, 30), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(fmtMB(_zipSize), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                      ])),
                      const Icon(Icons.change_circle_outlined, color: DzrTheme.accent),
                    ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Upload progress ──
          if (_upPct != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _upPct == 0 ? null : _upPct,
                minHeight: 9,
                color: DzrTheme.accent,
                backgroundColor: Colors.white.withOpacity(0.08),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _upPct! <= 0 ? 'Nyiapin upload…' : 'Upload ${(_upPct! * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
          ],

          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.rocket_launch_rounded),
            label: Text(_busy ? 'Lagi nge-upload…' : '🚀 Mulai Build'),
          ),
          const SizedBox(height: 14),
          Text(
            'Credit kepotong cuma kalo build sukses — sama persis kalo lu build via bot.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5),
          ),
        ]),
      ),
    );
  }

  Widget _section(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14));
}
