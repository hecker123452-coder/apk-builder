#!/usr/bin/env node
/**
 * dzr-install.js — pasang + integrasi dzr-integrity ke bot DZR di VPS
 *
 * Pemakaian:
 *   node dzr-install.js            -> deteksi + laporan (TANPA mengubah apa pun)
 *   node dzr-install.js --auto     -> deteksi + pasang hook (dengan backup) + pm2 restart
 *
 * Hook yang dipasang: LOG-ONLY by default (gak bisa ngerusak build).
 *   - Modul auto-lengkapi file project yang kurang SEBELUM build.
 *   - Set DZR_ENFORCE=1 (env pm2) kalau mau build diblokir saat project tetap gak lengkap.
 * Rollback: file asli di-backup ke <file>.bak-dzr-<timestamp>
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const MODE = process.argv.includes('--auto') ? 'auto' : 'report';
const MODULE_PATH = process.env.DZR_MODULE_PATH || '/opt/dzr/dzr-integrity.js';
const HOOK_TAG = 'DZR-INTEGRITY-HOOK v1';

function shOut(cmd) {
  try { return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
  catch (e) { return (e.stdout || '') + (e.stderr || ''); }
}

// ── 1. verifikasi modul ──
if (!fs.existsSync(MODULE_PATH)) {
  console.error('✘ Modul gak ada di ' + MODULE_PATH + ' — jalankan install.sh dulu.');
  process.exit(1);
}
try {
  const m = require(MODULE_PATH);
  if (typeof m.run !== 'function') throw new Error('export run() gak ketemu');
  console.log('✔ Modul integrity OK: ' + MODULE_PATH);
} catch (e) {
  console.error('✘ Modul rusak: ' + e.message);
  process.exit(1);
}

// ── 2. deteksi proses bot via pm2 ──
let procs = [];
try { procs = JSON.parse(shOut('pm2 jlist') || '[]'); } catch { /* pm2 gak ada */ }
const procsList = (Array.isArray(procs) ? procs : []).map((p) => ({
  name: p.name || '?',
  online: (p.pm2_env && p.pm2_env.status) || '?',
  cwd: (p.pm2_env && p.pm2_env.pm_cwd) || '',
  script: (p.pm2_env && p.pm2_env.pm_exec_path) || '',
})).filter((p) => p.script || p.cwd);

console.log('\n— Proses pm2: ' + (procsList.length ? '' : '(gak ada / pm2 gak terpasang)'));
procsList.forEach((p) => console.log(`  · ${p.name} [${p.online}] cwd=${p.cwd} script=${p.script}`));

// urutkan kandidat: nama mirip dzr/bot/build dulu
const cands = procsList.slice().sort((a, b) =>
  (/(dzr|bot|build|cloud)/i.test(b.name) ? 1 : 0) - (/(dzr|bot|build|cloud)/i.test(a.name) ? 1 : 0));

// ── 3. scan anchor di source bot ──
function scanFile(f) {
  let src = '';
  try { src = fs.readFileSync(f, 'utf8'); } catch { return null; }
  const lines = src.split('\n');
  const hits = [];
  lines.forEach((ln, i) => {
    const t = ln.trim();
    if (t.startsWith('//') || t.startsWith('*')) return;
    if (/(adm-zip|unzipper|AdmZip|unzip\s|extractAll|\.zip["'`])/i.test(ln)) hits.push({ t: 'zip', i: i + 1, ln: t.slice(0, 120) });
    if (/(spawn|execSync|execFile|exec)\s*\([^;\n]*(flutter|gradlew)/i.test(ln)) hits.push({ t: 'build', i: i + 1, ln: t.slice(0, 120) });
  });
  return { src, lines, hits };
}

const reports = [];
for (const c of cands.slice(0, 3)) {
  const files = new Set();
  if (c.script && /\.js$/.test(c.script)) files.add(c.script);
  if (c.cwd) {
    const walk = (d, depth) => {
      if (depth > 2 || files.size > 80) return;
      let es;
      try { es = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
      for (const e of es) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) { if (!/node_modules|\.git|^build$|^dist$|\.pm2/i.test(e.name)) walk(p, depth + 1); }
        else if (/\.js$/.test(e.name) && !/\.min\.js$/.test(e.name)) files.add(p);
      }
    };
    walk(c.cwd, 0);
  }
  for (const f of files) {
    const r = scanFile(f);
    if (r && r.hits.length) reports.push({ proc: c.name, file: f, ...r });
  }
}

console.log('\n— Anchor integrasi ditemukan: ' + (reports.length ? '' : '(gak ada — kirim output ini ke asisten)'));
reports.forEach((r) => {
  console.log(`  [${r.proc}] ${r.file}`);
  r.hits.slice(0, 10).forEach((h) => console.log(`    L${h.i} (${h.t}): ${h.ln}`));
});

if (MODE !== 'auto') {
  console.log('\nMODE REPORT — gak ada file yang diubah, gak ada yang di-restart.');
  console.log('Lanjut pasang otomatis: node ' + path.join(path.dirname(MODULE_PATH), 'dzr-install.js') + ' --auto');
  process.exit(0);
}

// ── 4. auto-patch: target = file dengan anchor BUILD (titik sebelum build dijalankan) ──
const buildReps = reports.filter((r) => r.hits.some((h) => h.t === 'build'));
const target = buildReps[0];
if (!target) {
  console.error('\n✘ Gak ada anchor "build" yang aman buat auto-patch.');
  console.error('  Kirim laporan di atas ke asisten buat dapet patch manual yang presisi.');
  process.exit(1);
}
if (target.src.includes(HOOK_TAG)) {
  console.log('\n✔ Hook sudah terpasang sebelumnya di ' + target.file + ' — skip.');
  process.exit(0);
}

// ekstrak ekspresi cwd dari sekitar baris build (cwd: X / const X = path.join(...))
const buildHit = target.hits.find((h) => h.t === 'build');
let projExpr = 'process.cwd()';
const window = target.lines.slice(Math.max(0, buildHit.i - 15), buildHit.i + 15).join('\n');
const mCwd = window.match(/cwd\s*:\s*([A-Za-z0-9_$.\[\]'"()+\s]+?),\s*\n/) || window.match(/cwd\s*:\s*([A-Za-z0-9_$.\[\]'"()]+)/);
if (mCwd) {
  projExpr = mCwd[1].trim().replace(/,+$/, '');
} else {
  const mVar = window.match(/(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*path\.join\(/);
  if (mVar) projExpr = mVar[1];
}
const isLiteral = /^['"].*['"]$/.test(projExpr);
console.log(`\n— Target patch: ${target.file} (sebelum L${buildHit.i})`);
console.log(`  projectDir = ${projExpr}${isLiteral ? '' : '  (variabel)'}`);

// hook: FIX dulu, log hasil, ENFORCE opsional via env DZR_ENFORCE=1
const hook = [
  `// >>> ${HOOK_TAG} (${new Date().toISOString()}) — pasang otomatis, backup: <file>.bak-dzr`,
  `try {`,
  `  const { run: __dzrIntegrity } = require(${JSON.stringify(MODULE_PATH)});`,
  `  const __dzrRep = __dzrIntegrity({ projectDir: ${projExpr} });`,
  `  console.log('[DZR-INTEGRITY]', JSON.stringify({ complete: __dzrRep.complete, fixed: __dzrRep.fixed, missing: __dzrRep.missing, errors: __dzrRep.errors }));`,
  `  if (process.env.DZR_ENFORCE === '1' && !__dzrRep.complete) throw new Error('[DZR-INTEGRITY] project gak lengkap: ' + (__dzrRep.errors.join('; ') || __dzrRep.missing.join('; ')));`,
  `} catch (__dzrE) { console.error('[DZR-INTEGRITY] hook:', __dzrE.message); }`,
  `// <<< ${HOOK_TAG}`,
].join('\n');

// backup + sisip
const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const backup = target.file + '.bak-dzr-' + ts;
fs.copyFileSync(target.file, backup);
const lines = target.lines;
const idx = buildHit.i - 1; // sisip DI ATAS baris build
lines.splice(idx, 0, hook, '');
fs.writeFileSync(target.file, lines.join('\n'), 'utf8');

// verifikasi sintaks
const check = shOut(`node --check ${JSON.stringify(target.file)}`);
if (/Error/i.test(check)) {
  fs.copyFileSync(backup, target.file);
  console.error('\n✘ Sintaks jadi error setelah patch — DIPULIHKAN dari backup. Kirim output ini ke asisten.');
  console.error(check);
  process.exit(1);
}
console.log('✔ Hook terpasang (sintaks OK): ' + target.file + ':' + (idx + 1));
console.log('  Backup: ' + backup);

// restart proses terkait
const procName = target.proc;
if (procName && procName !== '?') {
  const rs = shOut('pm2 restart ' + JSON.stringify(procName));
  const ok = /online|restart/i.test(rs);
  console.log((ok ? '✔' : '⚠') + ' pm2 restart ' + procName + (ok ? '' : ' — cek manual: pm2 ls'));
} else {
  console.log('⚠ Restart manual: pm2 restart <nama-bot>');
}

console.log('\n— Verifikasi:');
console.log('  pm2 logs ' + procName + ' --lines 30   (cari baris [DZR-INTEGRITY])');
console.log('  DZR_ENFORCE=1 di env pm2 = mode ketat (build diblokir kalau project tetap gak lengkap)');
console.log('— Rollback kalau ada masalah:');
console.log(`  cp ${backup} ${target.file} && pm2 restart ${procName}`);
