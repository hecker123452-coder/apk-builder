import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:typed_data';

/// 🔌 Klien REST API buat DZR CloudBuilder.
///
/// SEMUA komunikasi lewat HTTP native (dio) — TIDAK ADA WebView di app ini.
/// Auth: `Authorization: Bearer <key>` — key di-issue bot via /getappkey.
class DzrApi {
  DzrApi._();
  static final DzrApi I = DzrApi._();

  /// URL server — bisa di-override pas compile:
  /// flutter build apk --dart-define=DZR_API_URL=http://host:3000
  static const String defaultBaseUrl = String.fromEnvironment(
    'DZR_API_URL',
    defaultValue: 'http://66.33.22.227:3000',
  );

  String baseUrl = defaultBaseUrl;
  String? _key;
  Dio? _dio;

  String? get key => _key;

  void configure({required String baseUrl, String? key}) {
    final b = baseUrl.trim();
    this.baseUrl = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
    _key = (key == null || key.trim().isEmpty) ? null : key.trim();
    _dio = null; // rebuild client
  }

  Dio get dio {
    final d = _dio;
    if (d != null) return d;
    final nd = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(minutes: 20),
      headers: {
        if (_key != null) 'Authorization': 'Bearer $_key',
      },
      validateStatus: (_) => true, // status di-handle manual
      responseType: ResponseType.json,
    ));
    _dio = nd;
    return nd;
  }

  /// Dio khusus file besar (timeout lebih longgar).
  Dio get bigDio => Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 30),
        headers: {
          if (_key != null) 'Authorization': 'Bearer $_key',
        },
        validateStatus: (_) => true,
      ));

  ApiException _err(Response? r) {
    final code = r?.statusCode ?? 0;
    String msg = 'Server gak respond (${code == 0 ? 'koneksi gagal' : code}).';
    final data = r?.data;
    if (data is Map && data['msg'] is String && (data['msg'] as String).isNotEmpty) {
      msg = data['msg'] as String;
    } else if (code == 401) {
      msg = 'Key gak valid / udah di-rotate. /getappkey di bot buat key baru.';
    } else if (code == 500) {
      msg = 'Server error — coba lagi.';
    }
    return ApiException(code, msg);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final r = await dio.get(path);
    if (r.statusCode != 200) throw _err(r);
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<Map<String, dynamic>> post(String path) async {
    final r = await dio.post(path);
    if ((r.statusCode ?? 0) >= 400) throw _err(r);
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<Map<String, dynamic>> info() => getJson('/api/v1/info');
  Future<Map<String, dynamic>> me() => getJson('/api/v1/me');
  Future<Map<String, dynamic>> top() => getJson('/api/v1/top');
  Future<Map<String, dynamic>> job() => getJson('/api/v1/job');
  Future<Map<String, dynamic>> history() => getJson('/api/v1/history');
  Future<Map<String, dynamic>> files() => getJson('/api/v1/builds/files');
  Future<Map<String, dynamic>> cancelJob() => post('/api/v1/job/cancel');

  /// Upload ZIP project → pipeline build yang SAMA dengan bot.
  /// Body = raw octet-stream (bukan multipart) — server pipe langsung ke disk.
  Future<Map<String, dynamic>> uploadZip({
    required Uint8List bytes,
    required String filename,
    required String type, // flutter | kotlin
    required String build, // release | debug
    String? appName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final r = await dio.post(
      '/api/v1/builds',
      data: bytes, // Uint8List → dio set Content-Length otomatis → progress jalan
      onSendProgress: onProgress,
      options: Options(headers: {
        'Content-Type': 'application/octet-stream',
        'X-Filename': filename,
      }, sendTimeout: const Duration(minutes: 25), receiveTimeout: const Duration(minutes: 5)),
      queryParameters: {
        'type': type,
        'build': build,
        if (appName != null && appName.trim().isNotEmpty) 'name': appName.trim(),
      },
    );
    if ((r.statusCode ?? 0) >= 400) throw _err(r);
    return Map<String, dynamic>.from(r.data as Map);
  }

  /// Download APK hasil build ke [savePath] (native file IO, bukan webview).
  Future<void> downloadFile(String urlPath, String savePath,
      {void Function(int, int)? onProgress}) async {
    await bigDio.download(urlPath, savePath, onReceiveProgress: onProgress);
  }
}

class ApiException implements Exception {
  final int code;
  final String message;
  ApiException(this.code, this.message);
  @override
  String toString() => message;
}

/// helper buat baca JSON list-of-map dari response API
List<Map<String, dynamic>> asListOfMaps(dynamic v) {
  if (v is List) {
    return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return [];
}

String fmtMB(dynamic size) {
  final b = (size is num) ? size.toDouble() : double.tryParse('$size') ?? 0;
  if (b <= 0) return '0 MB';
  return '${(b / 1048576).toStringAsFixed(1)} MB';
}

String fmtDurationSec(dynamic sec) {
  final n = (sec is num) ? sec.toInt() : int.tryParse('$sec') ?? 0;
  if (n <= 0) return '—';
  final m = n ~/ 60, s = n % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

String fmtTimeAgo(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '—';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'baru aja';
  if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
  if (d.inHours < 24) return '${d.inHours} jam lalu';
  return '${d.inDays} hari lalu';
}

String fmtExpiry(int? expiresAtMs) {
  if (expiresAtMs == null || expiresAtMs <= 0) return '—';
  final left = expiresAtMs - DateTime.now().millisecondsSinceEpoch;
  if (left <= 0) return 'kehapus';
  final h = left ~/ 3600000;
  final m = (left % 3600000) ~/ 60000;
  return h > 0 ? '$h jam $m menit lagi' : '$m menit lagi';
}

/// Nama pendek buat UI
String shortName(String? s, [int max = 24]) {
  final v = (s ?? '').trim();
  if (v.isEmpty) return '—';
  return v.length > max ? '${v.substring(0, max - 1)}…' : v;
}
