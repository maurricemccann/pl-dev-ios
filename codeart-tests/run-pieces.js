// Runs every piece in the gallery's bundles through the prelude against a mock of the native bridge.
// Proves the JS side: the bundles evaluate unchanged, every piece makes and draws, and no call the pieces use is missing.
// Usage: node run-pieces.js <gallery repo root> [frames] [onlyId]
const vm = require('vm'), fs = require('fs'), path = require('path');
const root = process.argv[2] || 'C:/dev/pl-curves-gallery';
const FR = +(process.argv[3] || 6), ONLY = process.argv[4] || '';
const prelude = fs.readFileSync(path.join(__dirname, 'prelude.js'), 'utf8');
const bundles = JSON.parse(fs.readFileSync(path.join(root, 'lib/piece-bundles.json'), 'utf8')).files;
const sb = {}; const logs = []; const op = {}; let flushes = 0, opsTotal = 0, gl = 0, imgs = 0;
const t0 = Date.now();
sb.__N = {
  now: () => Date.now() - t0, log: (l, m) => { if (l >= 1) logs.push(l + ' ' + m); },
  canvasNew: () => 0, canvasResize: () => {}, canvasFree: () => {},
  flush: (id, nums, n, strs) => {
    flushes++; opsTotal += n;
    // walk the stream the way native does; an unknown opcode or a short record is a bug in the encoder
    const ARGS = { 1: 0, 2: 0, 3: 2, 4: 2, 5: 1, 6: 6, 7: 6, 8: 0, 9: 2, 10: 2, 11: 6, 12: 4, 13: 6, 14: 5, 15: 8, 16: 4, 17: 0, 18: 1, 19: 0, 20: 1, 21: 4, 22: 4, 23: 4, 24: 1, 25: 1, 26: 1, 27: 1, 28: 1, 29: 1, 30: 1, 31: 1, 32: 1, 33: 1, 34: 1, 35: 1, 36: 1, 37: 1, 38: 1, 39: 1, 40: 1, 41: 1, 42: 1, 43: 4, 44: 4, 45: 10, 47: 1, 48: 1, 49: 8, 50: 3, 51: 4, 52: 2, 53: 1, 54: 2, 55: 1, 56: 1, 57: 7 };
    let i = 0;
    while (i < n) {
      const c = nums[i++]; op[c] = (op[c] || 0) + 1;
      if (c === 46) { i += 1 + Math.min(nums[i], 8); continue; }
      const a = ARGS[c]; if (a === undefined) throw new Error('unknown opcode ' + c);
      for (let k = 0; k < a; k++) if (typeof nums[i + k] !== 'number' || Number.isNaN(nums[i + k])) throw new Error('bad arg op ' + c + ' #' + k + ' = ' + nums[i + k]);
      // string refs must exist
      if ([24, 25, 35, 36, 40, 55].includes(c) && !(strs[nums[i]] !== undefined)) throw new Error('missing string for op ' + c);
      if ([43, 44].includes(c) && !(strs[nums[i]] !== undefined)) throw new Error('missing text string');
      if ([52, 53, 54].includes(c) && !(strs[nums[i]] !== undefined)) throw new Error('missing path string');
      if (c === 50 && !(strs[nums[i + 2]] !== undefined)) throw new Error('missing gradient colour string');
      i += a;
    }
  },
  getImageData: () => {}, putImageData: () => {}, measureText: (f, t) => t.length * 6, hasFont: () => true, pointIn: () => 0,
  imageLoad: (id, url) => { imgs++; setImmediate(() => sb.__imgDone(id, 0, 0, 0)); },
  glDraw: () => { gl++; },
  fetch: (id, url) => {
    const p = path.join(root, 'public', url.replace(/^\//, '').split('?')[0]);
    setImmediate(() => { try { sb.__fetchDone(id, 200, fs.readFileSync(p, 'utf8')); } catch (e) { sb.__fetchDone(id, 404, ''); } });
  },
};
vm.createContext(sb); vm.runInContext(prelude, sb, { filename: 'prelude.js' });
for (const f of bundles) { const t = Date.now(); try { vm.runInContext(fs.readFileSync(path.join(root, 'public/scripts', f), 'utf8'), sb, { filename: f }); console.log('bundle', f, 'ok', Date.now() - t, 'ms'); } catch (e) { console.log('bundle', f, 'THREW', e.message); } }
const list = JSON.parse(sb.__listPieces());
console.log('pieces:', list.length, 'live:', list.filter((p) => p.live).length, 'shader (glsl tag):', list.filter((p) => (p.tags || []).includes('shader')).length);
(async () => {
  let ok = 0, bad = [];
  for (const p of list) {
    if (ONLY && p.id !== ONLY) continue;
    const before = logs.length;
    try {
      if (p.comp) { try { await sb.PL_loadComp(String(p.comp).padStart(2, '0')); } catch (e) { /* the app proceeds too */ } }
      const r = JSON.parse(sb.__newInstance(p.id, 780, 1688, 2)); if (r.error) { bad.push(p.id + ': ' + r.error); continue; }
      sb.__warm(r.handle, 4); let errs = 0; for (let f = 0; f < FR; f++) errs = sb.__draw(r.handle, -1);
      sb.__drawXf(r.handle, 99, 1.2, 10, 0.9, 0.2, true);
      sb.__freeInstance(r.handle);
      if (errs > 0 || logs.length > before) bad.push(p.id + ': ' + logs.slice(before).slice(0, 2).join(' | ')); else ok++;
    } catch (e) { bad.push(p.id + ' THREW ' + e.message); }
    await new Promise((r) => setImmediate(r));
  }
  console.log('ok', ok, 'bad', bad.length, 'flushes', flushes, 'ops', opsTotal, 'gl draws', gl, 'image loads', imgs);
  console.log('opcodes used:', Object.keys(op).sort((a, b) => a - b).join(' '));
  bad.slice(0, 60).forEach((b) => console.log(' ', b.slice(0, 220)));
  if (bad.length > 60) console.log('  ... and', bad.length - 60, 'more');
})();
