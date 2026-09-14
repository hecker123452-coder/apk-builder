#!/usr/bin/env node
/**
 * dzr-integrity.js — Integrity check + auto-complete project ZIP (DZR CloudBuilder)
 *
 * Port setia dari pipeline build.yml v5.6 (GitHub Actions) ke Node.js murni,
 * buat dipasang di bot VPS. Desain: idempotent, gak pernah ngerusak file
 * existing, fail-loud kalau ada yang gak bisa diperbaiki otomatis.
 *
 * Pemakaian (CLI):
 *   node dzr-integrity.js <project_dir>              -> cek + auto-complete, print laporan
 *   node dzr-integrity.js --zip <file.zip> <outdir>  -> validasi ZIP + extract + cek + auto-complete
 *
 * Pemakaian (modul, dari kode bot):
 *   const { run } = require('./dzr-integrity.js');
 *   const report = run({ zip: '/tmp/upload.zip', outDir: '/tmp/build-xyz' });
 *   // atau: run({ projectDir: '/tmp/build-xyz' })
 *   // report = { ok, projectType, complete, fixed[], missing[], errors[], projectDir }
 *
 * Aturan kelengkapan FLUTTER:
 *   - pubspec.yaml              WAJIB (gak bisa digenerasi — fail dengan pesan jelas)
 *   - android/ + manifest       auto-generate via `flutter create` (org com.dzrbuild)
 *   - lib/main.dart             auto-generate (minimal app valid)
 *   - folder assets di pubspec  auto-buat folder kosong
 * Aturan kelengkapan KOTLIN (validasi + laporan; auto-fix terbatas):
 *   - settings.gradle(.kts), app/build.gradle(.kts), AndroidManifest.xml, src dir
 */

'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

// ───────────────────────── helpers ─────────────────────────

function sh(cmd, opts = {}) {
  return execSync(cmd, Object.assign({ encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }, opts));
}
function shAllow(cmd, opts = {}) {
  try { return sh(cmd, opts); } catch (e) { return (e.stdout || '') + (e.stderr || ''); }
}

function isZip(file) {
  const fd = fs.openSync(file, 'r');
  const buf = Buffer.alloc(4);
  fs.readSync(fd, buf, 0, 4, 0);
  fs.closeSync(fd);
  return buf[0] === 0x50 && buf[1] === 0x4b && (buf[2] === 0x03 || buf[2] === 0x05 || buf[2] === 0x07);
}

function extractZip(zip, dest) {
  fs.mkdirSync(dest, { recursive: true });
  // coba unzip dulu, fallback ke python3 zipfile (selalu ada di VPS)
  const out = shAllow(`unzip -q ${JSON.stringify(zip)} -d ${JSON.stringify(dest)}`);
  if (out && /cannot|error|not found/i.test(out) && !fs.readdirSync(dest).length) {
    shAllow(`python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" ${JSON.stringify(zip)} ${JSON.stringify(dest)}`);
  }
  if (!fs.readdirSync(dest).length) throw new Error('ZIP gagal di-extract (kosong / korup)');
}

// cari root project: pubspec.yaml di root, atau maxdepth 3
function findProjectRoot(dir, kind) {
  const marker = kind === 'kotlin' ? 'settings.gradle' : 'pubspec.yaml';
  const markers = kind === 'kotlin'
    ? ['settings.gradle', 'settings.gradle.kts']
    : ['pubspec.yaml'];
  if (markers.some((m) => fs.existsSync(path.join(dir, m)))) return dir;
  // BFS maxdepth 3
  const queue = [{ d: dir, depth: 0 }];
  let best = null;
  while (queue.length) {
    const { d, depth } = queue.shift();
    if (depth > 3) continue;
    let entries;
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch { continue; }
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith('.') || e.name === 'node_modules') continue;
      const sub = path.join(d, e.name);
      if (markers.some((m) => fs.existsSync(path.join(sub, m)))) return sub;
      if (!best) best = sub;
      queue.push({ d: sub, depth: depth + 1 });
    }
  }
  return null;
}

function detectProjectType(dir) {
  if (fs.existsSync(path.join(dir, 'pubspec.yaml'))) return 'flutter';
  const km = ['settings.gradle', 'settings.gradle.kts'];
  if (km.some((m) => fs.existsSync(path.join(dir, m)))) return 'kotlin';
  return null;
}

// ───────────────────────── pubspec helpers ─────────────────────────

function readPubspec(dir) {
  return fs.readFileSync(path.join(dir, 'pubspec.yaml'), 'utf8');
}
function writePubspec(dir, content) {
  fs.writeFileSync(path.join(dir, 'pubspec.yaml'), content, 'utf8');
}
function pubspecName(content) {
  const m = content.match(/^name:[ \t]*["']?([a-zA-Z0-9_]+)["']?[ \t]*$/m);
  return m ? m[1] : null;
}
function isFlutterProject(content) {
  return /flutter/.test(content) && /sdk:/.test(content);
}
function assetDirs(content) {
  // parsing line-based: entri di bawah flutter: > assets: — folder (diakhiri /) atau file
  const dirs = [];
  let inFlutter = false, inAssets = false;
  for (const raw of content.split('\n')) {
    const line = raw.replace(/\t/g, '  ');
    if (/^flutter:[ \t]*$/.test(line)) { inFlutter = true; inAssets = false; continue; }
    if (/^[A-Za-z_-]+:/.test(line)) { inFlutter = false; inAssets = false; continue; }
    if (inFlutter && /^\s{2}assets:[ \t]*$/.test(line)) { inAssets = true; continue; }
    if (inFlutter && inAssets) {
      const m = line.match(/^\s{2,}-\s*(.+?)\s*(?:#.*)?$/);
      if (m) {
        const p = m[1].trim().replace(/^["']|["']$/g, '');
        if (p && !p.startsWith('<')) dirs.push(p);
      } else if (/^\s{2}[A-Za-z_-]+:/.test(line)) {
        inAssets = false; // key lain di dalam flutter: (mis. uses-material-design di atas)
      }
    }
  }
  return dirs;
}

// ───────────────────────── Flutter auto-complete ─────────────────────────

function flutterBootstrap(report) {
  const dir = report.projectDir;
  // shell kosong android/ (tanpa manifest) dihapus dulu — persis v5.6b
  const manifest = path.join(dir, 'android/app/src/main/AndroidManifest.xml');
  if (fs.existsSync(path.join(dir, 'android')) && !fs.existsSync(manifest)) {
    fs.rmSync(path.join(dir, 'android'), { recursive: true, force: true });
    report.fixed.push('hapus android/ shell kosong (tanpa AndroidManifest)');
  }
  if (!fs.existsSync(path.join(dir, 'android'))) {
    const content = readPubspec(dir);
    if (!isFlutterProject(content)) {
      report.missing.push('android/ (pubspec gak nandain project Flutter — bootstrap di-skip)');
      return;
    }
    let pkg = (pubspecName(content) || 'app').toLowerCase().replace(/[^a-z0-9_]/g, '');
    if (!pkg) pkg = 'app';
    if (/^[0-9]/.test(pkg)) pkg = 'a' + pkg;
    const out = shAllow(`flutter create --platforms=android --org com.dzrbuild --project-name ${JSON.stringify(pkg)} .`, { cwd: dir });
    if (fs.existsSync(path.join(dir, 'android/app/src/main/AndroidManifest.xml'))) {
      report.fixed.push(`generate android/ via flutter create (pkg: ${pkg}, org: com.dzrbuild)`);
    } else {
      report.errors.push('flutter create gagal generate android/: ' + String(out).slice(-300));
    }
  }
}

function minimalMainDart(pkgName) {
  return [
    "import 'package:flutter/material.dart';",
    '',
    'void main() {',
    "  runApp(const _App());",
    '}',
    '',
    'class _App extends StatelessWidget {',
    '  const _App();',
    '  @override',
    '  Widget build(BuildContext context) {',
    '    return MaterialApp(',
    '      title: ' + JSON.stringify(pkgName || 'DZR App') + ',',
    '      home: Scaffold(',
    '        body: Center(child: Text(' + JSON.stringify(pkgName || 'DZR App') + ')),',
    '      ),',
    '    );',
    '  }',
    '}',
    '',
  ].join('\n');
}

function flutterCompleteMissing(report) {
  const dir = report.projectDir;
  const content = readPubspec(dir);
  const pkg = pubspecName(content);

  // lib/main.dart
  const mainDart = path.join(dir, 'lib/main.dart');
  if (!fs.existsSync(path.join(dir, 'lib'))) fs.mkdirSync(path.join(dir, 'lib'), { recursive: true });
  if (!fs.existsSync(mainDart)) {
    fs.writeFileSync(mainDart, minimalMainDart(pkg), 'utf8');
    report.fixed.push('generate lib/main.dart (app minimal valid)');
  }

  // android/ bootstrap
  flutterBootstrap(report);

  // asset dirs/files yang dideklarasi pubspec tapi foldernya gak ada
  for (const a of assetDirs(content)) {
    const isDir = a.endsWith('/');
    const rel = isDir ? a.slice(0, -1) : a;
    if (!rel || rel.includes('..')) continue;
    // entri FILE (tanpa trailing /) -> yang dibuat foldernya saja, bukan file-nya sebagai dir
    const target = isDir ? rel : path.dirname(rel);
    const abs = path.join(dir, target);
    if (target && !fs.existsSync(abs)) {
      try {
        fs.mkdirSync(abs, { recursive: true });
        report.fixed.push(`buat folder asset yang kurang: ${target}/`);
      } catch { /* ignore */ }
    }
  }
}

// ───────────────────────── pub get anti-conflict (port v5.2/v5.5) ─────────────────────────

function bumpConstraint(content, pkg, newver, fixed) {
  const pat = new RegExp('^(\\s*' + pkg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ':\\s*)([^\\n#]+?)(\\s*#.*)?$', 'm');
  const m = content.match(pat);
  if (!m) return content; // gak ada barisnya di pubspec → gak bisa di-bump
  const val = m[2].trim();
  if (val.includes(':') || !/\d/.test(val)) return content; // dep git/sdk/path — jangan disentuh
  const nv = newver.startsWith('^') ? newver : '^' + newver;
  if (val === nv) return content;
  // guard anti-downgrade: jangan turunin major (konflik "pin terlalu baru" gak bisa
  // diberesin dengan nurunin pin — biarin fallback pub upgrade yang urus)
  const curMaj = (val.match(/\d+/) || [null])[0];
  const newMaj = (nv.match(/\d+/) || [null])[0];
  if (curMaj !== null && newMaj !== null && parseInt(newMaj, 10) < parseInt(curMaj, 10)) return content;
  fixed.push(`${pkg}: ${val} -> ${nv}`);
  return content.replace(pat, (mm, p1, p2, p3) => p1 + nv + (p3 || ''));
}

function parsePubError(err) {
  // need[pkg] = versi caret yang diminta paket LAIN terhadap pkg
  // (dari semua bentuk "X depends on P ^v" / "X requires P ^v")
  const need = {};
  for (const [, pkg, ver] of err.matchAll(/(?:depends on|requires) ([a-z0-9_]+) \^(\d+\.\d+\.\d+)/g)) need[pkg] = ver;
  // nama-nama yang muncul di klausa terminal "depends on both A ^v and B ^v"
  // (= pin langsung user yang kelibat konflik)
  const bothNames = [];
  for (const m of err.matchAll(/depends on both ([a-z0-9_]+) \^[\d.]+(?: and ([a-z0-9_]+)(?: \^[\d.]+)?)?/g)) {
    bothNames.push(m[1]);
    if (m[2]) bothNames.push(m[2]);
  }
  // klausa lengkap buat analisis kasus 1/2 (v5.5)
  const clauses = [];
  for (const m of err.matchAll(/([a-z0-9_]+)((?:\s+[\^><=~]{0,2}[\d.]+)(?:\s*[<>]=?\s*[\d.]+)?)?(?:\s+from\s+git)?\s+(?:which\s+)?(?:depends on|requires)\s+([a-z0-9_]+)\s+([\^><=~]{0,2}[\d.]+(?:\s*[<>]=?\s*[\d.]+)?)/g)) {
    clauses.push([m[1], m[2] || '', m[3], m[4]]);
  }
  return { need, bothNames, clauses };
}

function rlim(rng) {
  const num = (rng.match(/[\d.]+/) || ['0'])[0];
  const parts = num.split('.').filter((x) => x !== '').map((x) => parseInt(x, 10) || 0);
  const lo = (parts.concat([0, 0, 0])).slice(0, 3);
  let hi = null;
  if (rng.trim().startsWith('^')) hi = [lo[0] + 1, 0, 0];
  const m = rng.match(/<\s*(\d+)\.(\d+)\.(\d+)/);
  if (m) hi = [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)];
  return [lo, hi];
}
function disjoint(r1, r2) {
  const [lo1, hi1] = rlim(r1);
  const [lo2, hi2] = rlim(r2);
  return (hi1 && cmp(lo2, hi1) >= 0) || (hi2 && cmp(lo1, hi2) >= 0);
}
function cmp(a, b) {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}
function caretOf(rng) {
  const m = rng.match(/[\^><=~]{0,2}(\d+(?:\.\d+){0,2})/);
  if (!m) return null;
  const parts = m[1].split('.').filter((x) => x !== '');
  while (parts.length < 3) parts.push('0');
  return '^' + parts.slice(0, 3).join('.');
}

function pubSmartFix(content, err, fixed) {
  const { need, bothNames, clauses } = parsePubError(err);

  // Kasus 0a: pin langsung user (dari klausa terminal "depends on both ...")
  // yang diminta paket lain di versi caret berbeda → bump ke versi permintaan
  for (const cand of new Set(bothNames)) {
    if (need[cand]) content = bumpConstraint(content, cand, need[cand], fixed);
  }
  if (fixed.length) return content;

  // Kasus 0b: bentuk "which requires/depends on X ^v" → bump pin X kalau ada
  for (const [, pkg, ver] of err.matchAll(/which (?:requires|depends on) ([a-z0-9_]+) \^(\d+\.\d+\.\d+)/g)) {
    content = bumpConstraint(content, pkg, ver, fixed);
  }
  if (fixed.length) return content;

  // Kasus 1 & 2 (v5.5): analisis klausa "X <range> depends on Y <range>"
  const cands = [...new Set(bothNames)];
  let bumped = false;

  // Kasus 2: kandidat jadi OBJEK dua klausa yang rentangnya berbenturan
  for (const cand of cands) {
    if (bumped) break;
    const rngs = clauses.filter(([sp, , dp]) => dp === cand && sp !== cand).map((x) => x[3]);
    for (let i = 0; i < rngs.length && !bumped; i++) {
      for (let j = i + 1; j < rngs.length; j++) {
        if (disjoint(rngs[i], rngs[j])) {
          const tgt = caretOf(rlim(rngs[i])[0] >= rlim(rngs[j])[0] ? rngs[i] : rngs[j]);
          if (tgt) { content = bumpConstraint(content, cand, tgt, fixed); bumped = true; }
          break;
        }
      }
    }
  }
  // Kasus 1: kandidat jadi SUBJEK klausa yang benturan
  if (!bumped) {
    for (const cand of cands) {
      if (bumped) break;
      for (const [sp, sr, dp, dr] of clauses) {
        if (sp !== cand || bumped) continue;
        const clash = clauses.some(([sp2, , dp2, dr2]) => dp2 === dp && sp2 !== cand && disjoint(dr, dr2));
        if (clash) {
          const m3 = sr.match(/\^(\d+)/);
          const m4 = sr.match(/<\s*(\d+)\./);
          if (m3) { content = bumpConstraint(content, cand, '^' + (parseInt(m3[1], 10) + 1) + '.0.0', fixed); bumped = true; }
          else if (m4) { content = bumpConstraint(content, cand, '^' + m4[1] + '.0.0', fixed); bumped = true; }
        }
      }
    }
  }
  return content;
}

function pubGetAntiConflict(report) {
  const dir = report.projectDir;
  const MAX = 4;
  for (let attempt = 1; attempt <= MAX; attempt++) {
    try {
      sh('flutter pub get', { cwd: dir, timeout: 300000 });
      report.fixed.push(`flutter pub get OK (percobaan ${attempt})`);
      return true;
    } catch (e) {
      const err = (e.stdout || '') + (e.stderr || '');
      report.logs.push(`pub get gagal (percobaan ${attempt}/${MAX})`);
      const content = readPubspec(dir);
      const fixed = [];
      const patched = pubSmartFix(content, err, fixed);
      if (fixed.length) {
        writePubspec(dir, patched);
        report.fixed.push('AUTO-FIX pubspec.yaml: ' + fixed.join('; '));
      } else {
        // fallback terakhir: pub upgrade --major-versions
        shAllow('flutter pub upgrade --major-versions', { cwd: dir, timeout: 600000 });
        report.fixed.push('fallback: flutter pub upgrade --major-versions');
      }
    }
  }
  report.errors.push('pub get tetap gagal setelah 4 percobaan auto-fix — konflik dependensi tidak bisa diselesaikan otomatis');
  return false;
}

// ───────────────────────── Kotlin validation ─────────────────────────

function kotlinCheck(report) {
  const dir = report.projectDir;
  const checks = [
    ['settings.gradle', 'settings.gradle.kts'],
    ['app/build.gradle', 'app/build.gradle.kts'],
    ['app/src/main/AndroidManifest.xml'],
  ];
  for (const alts of checks) {
    if (!alts.some((p) => fs.existsSync(path.join(dir, p)))) {
      report.missing.push('kotlin: ' + alts[0] + ' gak ada (gak bisa digenerasi otomatis)');
    }
  }
  // src dir minimal
  const src = path.join(dir, 'app/src/main/java');
  const srcK = path.join(dir, 'app/src/main/kotlin');
  if (!fs.existsSync(src) && !fs.existsSync(srcK)) {
    report.missing.push('kotlin: app/src/main/java|kotlin gak ada (gak ada source code)');
  }
}

// ───────────────────────── main ─────────────────────────

function run(opts) {
  const report = {
    ok: false,
    complete: false,
    projectType: null,
    projectDir: null,
    fixed: [],
    missing: [],
    errors: [],
    logs: [],
  };
  try {
    let workDir;
    if (opts.zip) {
      if (!fs.existsSync(opts.zip)) throw new Error('ZIP gak ketemu: ' + opts.zip);
      if (!isZip(opts.zip)) throw new Error('Bukan file ZIP valid (magic bytes salah)');
      extractZip(opts.zip, opts.outDir || fs.mkdtempSync(path.join(os.tmpdir(), 'dzrproj-')));
      workDir = opts.outDir;
      // flat-kan kalau semua isi ada dalam 1 folder pembungkus
      const root = findProjectRoot(workDir, 'flutter') || findProjectRoot(workDir, 'kotlin');
      if (root && root !== workDir) {
        // pindah isi root ke workDir (persis rsync --remove-source-files di workflow)
        for (const e of fs.readdirSync(root)) {
          fs.renameSync(path.join(root, e), path.join(workDir, e));
        }
        report.logs.push('flat-kan struktur: ' + path.relative(workDir, root) + ' -> ./');
      }
      report.projectDir = workDir;
    } else if (opts.projectDir) {
      report.projectDir = opts.projectDir;
    } else {
      throw new Error('opts.zip atau opts.projectDir wajib');
    }
    const dir = report.projectDir;

    const type = detectProjectType(dir);
    if (!type) {
      report.errors.push('Gak nemu pubspec.yaml (Flutter) atau settings.gradle (Kotlin) — project gak dikenali, gak ada yang bisa di-auto-complete');
      return report;
    }
    report.projectType = type;

    if (type === 'flutter') {
      const content = readPubspec(dir); // fail-loud kalau korup
      report.logs.push('pubspec.yaml OK (name: ' + (pubspecName(content) || '?') + ')');
      flutterCompleteMissing(report);
      // cek kelengkapan akhir
      report.complete =
        fs.existsSync(path.join(dir, 'pubspec.yaml')) &&
        fs.existsSync(path.join(dir, 'android/app/src/main/AndroidManifest.xml')) &&
        fs.existsSync(path.join(dir, 'lib/main.dart'));
      if (opts.pubGet !== false) pubGetAntiConflict(report);
    } else {
      kotlinCheck(report);
      report.complete = report.missing.length === 0;
    }

    report.ok = report.errors.length === 0;
    return report;
  } catch (e) {
    report.errors.push(e.message || String(e));
    return report;
  }
}

function printReport(r) {
  const line = '─'.repeat(60);
  console.log(line);
  console.log('DZR INTEGRITY REPORT');
  console.log(line);
  console.log('Tipe project :', r.projectType || '?');
  console.log('Dir          :', r.projectDir || '-');
  console.log('Lengkap      :', r.complete ? 'YA' : 'TIDAK');
  if (r.fixed.length) {
    console.log('\n✔ Diperbaiki otomatis:');
    r.fixed.forEach((f) => console.log('  - ' + f));
  }
  if (r.missing.length) {
    console.log('\n✘ Kurang (gak bisa auto):');
    r.missing.forEach((f) => console.log('  - ' + f));
  }
  if (r.errors.length) {
    console.log('\n‼ Error:');
    r.errors.forEach((f) => console.log('  - ' + f));
  }
  if (r.logs.length) {
    console.log('\nLog:');
    r.logs.forEach((f) => console.log('  · ' + f));
  }
  console.log(line);
  return r.ok ? 0 : 1;
}

if (require.main === module) {
  const argv = process.argv.slice(2);
  if (argv[0] === '--zip') {
    const [, zip, out] = argv;
    process.exit(printReport(run({ zip, outDir: out })));
  } else if (argv[0]) {
    process.exit(printReport(run({ projectDir: argv[0] })));
  } else {
    console.error('Pemakaian: node dzr-integrity.js <project_dir> | --zip <file.zip> <outdir>');
    process.exit(2);
  }
}

module.exports = { run, printReport, _internal: { pubSmartFix, assetDirs, pubspecName, bumpConstraint } };
