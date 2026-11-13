// PL DEV code art: the browser surface his pieces expect, running inside JavaScriptCore.
// Canvas 2D calls are recorded as numbers into one Float64Array and sent to native in a single flush, so a frame costs a
// handful of bridge calls, not thousands. Native object: __N (see CodeArtBridge.swift). Nothing here touches the network
// except through __N.fetch / __N.imageLoad, which resolve against the gallery.
(function (G) {
  'use strict';
  const N = G.__N;
  G.window = G; G.self = G; G.top = G; G.parent = G; G.globalThis = G;
  G.devicePixelRatio = 2; G.innerWidth = 390; G.innerHeight = 844;
  G.navigator = { userAgent: 'PLDev/1 (iPhone) JavaScriptCore', maxTouchPoints: 5, hardwareConcurrency: 4, language: 'en-US', platform: 'iPhone' };
  G.location = { href: '', search: '', origin: '', pathname: '/', hash: '' };
  G.performance = { now: () => N.now() };
  const fmt = (a) => Array.prototype.map.call(a, (x) => { try { return typeof x === 'string' ? x : (x && x.stack) || JSON.stringify(x); } catch (e) { return String(x); } }).join(' ');
  G.console = { log() { N.log(0, fmt(arguments)); }, info() { N.log(0, fmt(arguments)); }, debug() {}, warn() { N.log(1, fmt(arguments)); }, error() { N.log(2, fmt(arguments)); }, trace() {} };

  // ---- timers, pumped by native once a frame ----
  let TID = 0; const timers = new Map(); const rafs = [];
  G.setTimeout = (fn, ms, ...a) => { const id = ++TID; timers.set(id, { fn, at: N.now() + (+ms || 0), a, every: 0 }); return id; };
  G.setInterval = (fn, ms, ...a) => { const id = ++TID; ms = Math.max(1, +ms || 0); timers.set(id, { fn, at: N.now() + ms, a, every: ms }); return id; };
  G.clearTimeout = G.clearInterval = (id) => { timers.delete(id); };
  G.requestAnimationFrame = (fn) => { rafs.push(fn); return rafs.length; };
  G.cancelAnimationFrame = () => {};
  G.__pump = () => {
    const now = N.now();
    for (const [id, t] of Array.from(timers)) { if (t.at <= now) { if (t.every) t.at = now + t.every; else timers.delete(id); try { t.fn.apply(null, t.a); } catch (e) { N.log(2, 'timer: ' + e); } } }
    const r = rafs.splice(0); for (const f of r) { try { f(now); } catch (e) { N.log(2, 'raf: ' + e); } }
  };

  // ---- audio: the one object every piece reads ----
  const A = G.__VJ_AUDIO = { bass: 0, mid: 0, high: 0, beat: false };
  G.__setAudio = (b, m, h, beat) => { A.bass = b; A.mid = m; A.high = h; A.beat = !!beat; };

  // ---- ops ----
  const OP = { SAVE: 1, RESTORE: 2, TRANSLATE: 3, SCALE: 4, ROTATE: 5, TRANSFORM: 6, SETTRANSFORM: 7, BEGINPATH: 8, MOVETO: 9, LINETO: 10, BEZIER: 11, QUAD: 12, ARC: 13, ARCTO: 14, ELLIPSE: 15, RECT: 16, CLOSEPATH: 17,
    FILL: 18, STROKE: 19, CLIP: 20, FILLRECT: 21, STROKERECT: 22, CLEARRECT: 23, FILLSTYLE: 24, STROKESTYLE: 25, FILLGRAD: 26, STROKEGRAD: 27, FILLPAT: 28, STROKEPAT: 29, LINEWIDTH: 30, LINECAP: 31, LINEJOIN: 32,
    MITER: 33, ALPHA: 34, COMPOSITE: 35, SHADOWCOLOR: 36, SHADOWBLUR: 37, SHADOWOX: 38, SHADOWOY: 39, FONT: 40, TEXTALIGN: 41, TEXTBASELINE: 42, FILLTEXT: 43, STROKETEXT: 44, DRAWIMAGE: 45, LINEDASH: 46,
    DASHOFFSET: 47, SMOOTHING: 48, GRADDEF: 49, GRADSTOP: 50, PATDEF: 51, FILLPATH: 52, STROKEPATH: 53, CLIPPATH: 54, FILTER: 55, LETTERSPACING: 56, PATXF: 57 };
  const dirty = new Set();
  let CANVAS_ID = 0;
  const reg = typeof FinalizationRegistry === 'function' ? new FinalizationRegistry((id) => { try { N.canvasFree(id); } catch (e) {} }) : null;

  class CanvasGradient { constructor(ctx, id) { this._ctx = ctx; this._id = id; } addColorStop(o, c) { this._ctx._op(OP.GRADSTOP, this._id, +o, this._ctx._s(c)); } }
  class DOMMatrix {
    constructor(i) { const v = i && i.length >= 6 ? i : [1, 0, 0, 1, 0, 0]; this.a = v[0]; this.b = v[1]; this.c = v[2]; this.d = v[3]; this.e = v[4]; this.f = v[5]; }
    _m(a, b, c, d, e, f) { const r = new DOMMatrix([this.a * a + this.c * b, this.b * a + this.d * b, this.a * c + this.c * d, this.b * c + this.d * d, this.a * e + this.c * f + this.e, this.b * e + this.d * f + this.f]); return r; }
    translate(x, y) { return this._m(1, 0, 0, 1, +x || 0, +y || 0); } scale(x, y) { return this._m(+x || 0, 0, 0, y === undefined ? +x || 0 : +y || 0, 0, 0); }
    rotate(deg) { const r = (+deg || 0) * Math.PI / 180, c = Math.cos(r), s = Math.sin(r); return this._m(c, s, -s, c, 0, 0); }
    multiply(o) { return this._m(o.a, o.b, o.c, o.d, o.e, o.f); } inverse() { const det = this.a * this.d - this.b * this.c || 1; return new DOMMatrix([this.d / det, -this.b / det, -this.c / det, this.a / det, (this.c * this.f - this.d * this.e) / det, (this.b * this.e - this.a * this.f) / det]); }
  }
  G.DOMMatrix = DOMMatrix; G.WebKitCSSMatrix = DOMMatrix;
  class CanvasPattern { constructor(ctx, id) { this._ctx = ctx; this._id = id; } setTransform(m) { if (m) this._ctx._op(OP.PATXF, this._id, m.a, m.b, m.c, m.d, m.e, m.f); } }

  class ImageData {
    constructor(a, b, c) {
      if (typeof a === 'number') { this.width = a | 0; this.height = b | 0; this.data = new Uint8ClampedArray(this.width * this.height * 4); this.colorSpace = 'srgb'; }
      else { this.data = a; this.width = b | 0; this.height = c == null ? (a.length / 4 / this.width) | 0 : c | 0; this.colorSpace = 'srgb'; }
    }
  }
  G.ImageData = ImageData;

  const FONT_PX = /(\d+(?:\.\d+)?)px/;
  class Ctx2D {
    constructor(canvas) { this.canvas = canvas; this._ops = new Float64Array(1 << 15); this._n = 0; this._strs = []; this._smap = new Map(); this._gid = 0; this._stack = []; this._reset(); }
    _reset() {
      this._st = { fillStyle: '#000000', strokeStyle: '#000000', lineWidth: 1, lineCap: 'butt', lineJoin: 'miter', miterLimit: 10, globalAlpha: 1, globalCompositeOperation: 'source-over',
        shadowColor: 'rgba(0, 0, 0, 0)', shadowBlur: 0, shadowOffsetX: 0, shadowOffsetY: 0, font: '10px sans-serif', textAlign: 'start', textBaseline: 'alphabetic', imageSmoothingEnabled: true,
        imageSmoothingQuality: 'low', filter: 'none', letterSpacing: '0px', lineDashOffset: 0, dash: [] };
    }
    _s(str) { str = String(str); let i = this._smap.get(str); if (i === undefined) { i = this._strs.length; this._strs.push(str); this._smap.set(str, i); } return i; }
    _op(code, a, b, c, d, e, f, g, h, i, j) {
      if (this._n + 14 > this._ops.length) { this._grow(); }
      let n = this._n; const o = this._ops;
      o[n++] = code; const k = arguments.length;
      if (k > 1) { o[n++] = a; if (k > 2) { o[n++] = b; if (k > 3) { o[n++] = c; if (k > 4) { o[n++] = d; if (k > 5) { o[n++] = e; if (k > 6) { o[n++] = f; if (k > 7) { o[n++] = g; if (k > 8) { o[n++] = h; if (k > 9) { o[n++] = i; if (k > 10) { o[n++] = j; } } } } } } } } } }
      const first = this._n === 0; this._n = n;
      if (n > 24000) this._flush(); else if (first) dirty.add(this.canvas);
    }
    _grow() { if (this._n > 20000) { this._flush(); return; } const b = new Float64Array(this._ops.length * 2); b.set(this._ops); this._ops = b; }
    _flush() {
      if (!this._n) return; const c = this.canvas; c._sync();
      const n = this._n, s = this._strs; this._n = 0; this._strs = []; this._smap = new Map();
      try { N.flush(c._id, this._ops, n, s); } catch (e) { N.log(2, 'flush: ' + e); }
      dirty.delete(c);
    }
    // ---- state ----
    save() { this._stack.push(Object.assign({}, this._st, { dash: this._st.dash.slice() })); this._op(OP.SAVE); }
    restore() { const s = this._stack.pop(); if (s) { this._st = s; this._op(OP.RESTORE); } }
    reset() { this._stack.length = 0; this._reset(); this._n = 0; this._strs = []; this._smap = new Map(); this.canvas._clearNative(); }
    // ---- transforms ----
    translate(x, y) { this._op(OP.TRANSLATE, x, y); }
    scale(x, y) { this._op(OP.SCALE, x, y); }
    rotate(a) { this._op(OP.ROTATE, a); }
    transform(a, b, c, d, e, f) { this._op(OP.TRANSFORM, a, b, c, d, e, f); }
    setTransform(a, b, c, d, e, f) { if (a && typeof a === 'object') { f = a.f; e = a.e; d = a.d; c = a.c; b = a.b; a = a.a; } this._op(OP.SETTRANSFORM, a, b, c, d, e, f); }
    resetTransform() { this._op(OP.SETTRANSFORM, 1, 0, 0, 1, 0, 0); }
    getTransform() { return { a: 1, b: 0, c: 0, d: 1, e: 0, f: 0 }; }
    // ---- path ----
    beginPath() { this._op(OP.BEGINPATH); }
    moveTo(x, y) { this._op(OP.MOVETO, x, y); }
    lineTo(x, y) { this._op(OP.LINETO, x, y); }
    bezierCurveTo(a, b, c, d, e, f) { this._op(OP.BEZIER, a, b, c, d, e, f); }
    quadraticCurveTo(a, b, c, d) { this._op(OP.QUAD, a, b, c, d); }
    arc(x, y, r, a0, a1, ccw) { this._op(OP.ARC, x, y, r, a0, a1, ccw ? 1 : 0); }
    arcTo(x1, y1, x2, y2, r) { this._op(OP.ARCTO, x1, y1, x2, y2, r); }
    ellipse(x, y, rx, ry, rot, a0, a1, ccw) { this._op(OP.ELLIPSE, x, y, rx, ry, rot, a0, a1, ccw ? 1 : 0); }
    rect(x, y, w, h) { this._op(OP.RECT, x, y, w, h); }
    roundRect(x, y, w, h, r) {
      let tl, tr, br, bl; if (Array.isArray(r)) { tl = r[0] || 0; tr = r.length > 1 ? r[1] : tl; br = r.length > 2 ? r[2] : tl; bl = r.length > 3 ? r[3] : tr; } else { tl = tr = br = bl = +r || 0; }
      if (typeof tl === 'object') tl = tl.x || 0; if (typeof tr === 'object') tr = tr.x || 0; if (typeof br === 'object') br = br.x || 0; if (typeof bl === 'object') bl = bl.x || 0;
      this.moveTo(x + tl, y); this.lineTo(x + w - tr, y); this.arcTo(x + w, y, x + w, y + tr, tr); this.lineTo(x + w, y + h - br); this.arcTo(x + w, y + h, x + w - br, y + h, br);
      this.lineTo(x + bl, y + h); this.arcTo(x, y + h, x, y + h - bl, bl); this.lineTo(x, y + tl); this.arcTo(x, y, x + tl, y, tl); this.closePath();
    }
    closePath() { this._op(OP.CLOSEPATH); }
    fill(a, b) { if (a instanceof Path2D) this._op(OP.FILLPATH, this._s(a.d), b === 'evenodd' ? 1 : 0); else this._op(OP.FILL, a === 'evenodd' ? 1 : 0); }
    stroke(p) { if (p instanceof Path2D) this._op(OP.STROKEPATH, this._s(p.d)); else this._op(OP.STROKE); }
    clip(a, b) { if (a instanceof Path2D) this._op(OP.CLIPPATH, this._s(a.d), b === 'evenodd' ? 1 : 0); else this._op(OP.CLIP, a === 'evenodd' ? 1 : 0); }
    isPointInPath(p, x, y, rule) { if (!(p instanceof Path2D)) return false; return !!N.pointIn(p.d, +x, +y, rule === 'evenodd' ? 1 : 0, 0, 0); }
    isPointInStroke(p, x, y) { if (!(p instanceof Path2D)) return false; return !!N.pointIn(p.d, +x, +y, 0, 1, this._st.lineWidth); }
    // ---- rects ----
    fillRect(x, y, w, h) { this._op(OP.FILLRECT, x, y, w, h); }
    strokeRect(x, y, w, h) { this._op(OP.STROKERECT, x, y, w, h); }
    clearRect(x, y, w, h) { this._op(OP.CLEARRECT, x, y, w, h); }
    // ---- gradients, patterns ----
    createLinearGradient(x0, y0, x1, y1) { const id = ++this._gid; this._op(OP.GRADDEF, id, 0, x0, y0, 0, x1, y1, 0); return new CanvasGradient(this, id); }
    createRadialGradient(x0, y0, r0, x1, y1, r1) { const id = ++this._gid; this._op(OP.GRADDEF, id, 1, x0, y0, r0, x1, y1, r1); return new CanvasGradient(this, id); }
    createConicGradient(a, x, y) { const id = ++this._gid; this._op(OP.GRADDEF, id, 0, x, y, 0, x + 1, y, 0); return new CanvasGradient(this, id); }
    createPattern(src, rep) {
      const id = ++this._gid; const r = rep === 'no-repeat' ? 0 : rep === 'repeat-x' ? 2 : rep === 'repeat-y' ? 3 : 1;
      if (src instanceof CanvasEl) { src._sync(); if (src._ctx2) src._ctx2._flush(); this._op(OP.PATDEF, id, 0, src._id, r); this._flush(); }
      else if (src instanceof ImageEl) this._op(OP.PATDEF, id, 1, src._id, r);
      else return null;
      return new CanvasPattern(this, id);
    }
    // ---- text ----
    fillText(t, x, y, mw) { this._op(OP.FILLTEXT, this._s(t), x, y, mw == null ? -1 : mw); }
    strokeText(t, x, y, mw) { this._op(OP.STROKETEXT, this._s(t), x, y, mw == null ? -1 : mw); }
    measureText(t) {
      t = String(t); const f = this._st.font; const m = FONT_PX.exec(f); const px = m ? +m[1] : 10; const w = N.measureText(f, t, parseFloat(this._st.letterSpacing) || 0);
      return { width: w, actualBoundingBoxLeft: 0, actualBoundingBoxRight: w, actualBoundingBoxAscent: px * 0.8, actualBoundingBoxDescent: px * 0.2, fontBoundingBoxAscent: px * 0.9, fontBoundingBoxDescent: px * 0.25 };
    }
    // ---- images ----
    drawImage(img, a, b, c, d, e, f, g, h) {
      let kind, id, sw, sh;
      if (img instanceof CanvasEl) { img._sync(); if (img._ctx2) img._ctx2._flush(); kind = 0; id = img._id; sw = img._w; sh = img._h; }
      else if (img instanceof ImageEl) { if (!img.complete || !img.naturalWidth) return; kind = 1; id = img._id; sw = img.naturalWidth; sh = img.naturalHeight; }
      else return;
      const k = arguments.length; let sx = 0, sy = 0, dx, dy, dw, dh;
      if (k <= 3) { dx = a; dy = b; dw = sw; dh = sh; } else if (k <= 5) { dx = a; dy = b; dw = c; dh = d; } else { sx = a; sy = b; sw = c; sh = d; dx = e; dy = f; dw = g; dh = h; }
      if (!(sw > 0 && sh > 0)) return;
      this._op(OP.DRAWIMAGE, kind, id, sx, sy, sw, sh, dx, dy, dw, dh);
      if (kind === 0) this._flush(); // the source may change before this canvas is flushed: realise the copy now
    }
    getImageData(x, y, w, h) {
      x |= 0; y |= 0; w = Math.max(1, w | 0); h = Math.max(1, h | 0); this._flush(); this.canvas._sync();
      const d = new Uint8ClampedArray(w * h * 4); N.getImageData(this.canvas._id, x, y, w, h, d); return new ImageData(d, w, h);
    }
    putImageData(im, dx, dy, sx, sy, sw, sh) {
      this._flush(); this.canvas._sync(); const full = sx === undefined;
      N.putImageData(this.canvas._id, im.data, im.width, im.height, dx | 0, dy | 0, full ? 0 : sx | 0, full ? 0 : sy | 0, full ? im.width : sw | 0, full ? im.height : sh | 0);
    }
    createImageData(a, b) { return typeof a === 'number' ? new ImageData(a, b) : new ImageData(a.width, a.height); }
    setLineDash(a) { const arr = Array.prototype.slice.call(a || []).map(Number); this._st.dash = arr.length % 2 ? arr.concat(arr) : arr; this._op.apply(this, [OP.LINEDASH, this._st.dash.length].concat(this._st.dash.slice(0, 8))); }
    getLineDash() { return this._st.dash.slice(); }
    drawFocusIfNeeded() {} scrollPathIntoView() {}
  }
  // style and numeric properties: emit only when the value changes
  const PROPS = {
    lineWidth: [OP.LINEWIDTH, 'n'], lineCap: [OP.LINECAP, { butt: 0, round: 1, square: 2 }], lineJoin: [OP.LINEJOIN, { miter: 0, round: 1, bevel: 2 }], miterLimit: [OP.MITER, 'n'], globalAlpha: [OP.ALPHA, 'n'],
    shadowBlur: [OP.SHADOWBLUR, 'n'], shadowOffsetX: [OP.SHADOWOX, 'n'], shadowOffsetY: [OP.SHADOWOY, 'n'], lineDashOffset: [OP.DASHOFFSET, 'n'],
    textAlign: [OP.TEXTALIGN, { start: 0, left: 0, center: 1, end: 2, right: 2 }], textBaseline: [OP.TEXTBASELINE, { alphabetic: 0, top: 1, hanging: 2, middle: 3, ideographic: 4, bottom: 5 }],
    imageSmoothingEnabled: [OP.SMOOTHING, 'b'], globalCompositeOperation: [OP.COMPOSITE, 's'], shadowColor: [OP.SHADOWCOLOR, 's'], font: [OP.FONT, 's'], filter: [OP.FILTER, 's'], letterSpacing: [OP.LETTERSPACING, 'px'],
  };
  for (const name of Object.keys(PROPS)) {
    const code = PROPS[name][0], kind = PROPS[name][1];
    Object.defineProperty(Ctx2D.prototype, name, {
      get() { return this._st[name]; },
      set(v) {
        if (kind === 'n') { v = +v; if (!isFinite(v)) return; if (name === 'lineWidth' && !(v > 0)) return; } else if (kind === 'b') v = !!v; else if (kind === 'px') { v = String(v); }
        if (this._st[name] === v) return; this._st[name] = v;
        if (kind === 'n') this._op(code, v); else if (kind === 'b') this._op(code, v ? 1 : 0); else if (kind === 's') this._op(code, this._s(v)); else if (kind === 'px') this._op(code, parseFloat(v) || 0); else this._op(code, kind[v] === undefined ? 0 : kind[v]);
      },
    });
  }
  Object.defineProperty(Ctx2D.prototype, 'imageSmoothingQuality', { get() { return this._st.imageSmoothingQuality; }, set(v) { this._st.imageSmoothingQuality = v; } });
  for (const name of ['fillStyle', 'strokeStyle']) {
    const isFill = name === 'fillStyle';
    Object.defineProperty(Ctx2D.prototype, name, {
      get() { return this._st[name]; },
      set(v) {
        if (v instanceof CanvasGradient) { this._st[name] = v; this._op(isFill ? OP.FILLGRAD : OP.STROKEGRAD, v._id); }
        else if (v instanceof CanvasPattern) { this._st[name] = v; this._op(isFill ? OP.FILLPAT : OP.STROKEPAT, v._id); }
        else { v = String(v); if (this._st[name] === v) return; this._st[name] = v; this._op(isFill ? OP.FILLSTYLE : OP.STROKESTYLE, this._s(v)); }
      },
    });
  }

  // ---- WebGL: a fragment-shader-only stub. shaderPiece() runs unchanged; the draw is a Metal pass in native ----
  const U_SLOT = { u_time: 0, u_res: 1, u_bass: 3, u_mid: 4, u_high: 5, u_beat: 6, u_gold: 7, u_ink: 10, u_bg: 13 };
  class GLStub {
    constructor(canvas) { this.canvas = canvas; this._frag = ''; this._u = new Float64Array(16); Object.assign(this, { VERTEX_SHADER: 35633, FRAGMENT_SHADER: 35632, COMPILE_STATUS: 35713, LINK_STATUS: 35714, ARRAY_BUFFER: 34962, STATIC_DRAW: 35044, FLOAT: 5126, TRIANGLES: 4 }); }
    createShader(t) { return { t, src: '' }; } shaderSource(s, src) { s.src = src; } compileShader() {} getShaderParameter() { return true; } getShaderInfoLog() { return ''; } deleteShader() {}
    createProgram() { return { sh: [] }; } attachShader(p, s) { p.sh.push(s); if (s.t === 35632) this._frag = s.src; } linkProgram() {} getProgramParameter() { return true; } getProgramInfoLog() { return ''; } useProgram() {} deleteProgram() {}
    createBuffer() { return {}; } bindBuffer() {} bufferData() {} deleteBuffer() {} getAttribLocation() { return 0; } enableVertexAttribArray() {} vertexAttribPointer() {} viewport() {}
    getUniformLocation(p, name) { const s = U_SLOT[name]; return s === undefined ? null : { slot: s }; }
    uniform1f(l, v) { if (l) this._u[l.slot] = v; } uniform2f(l, a, b) { if (l) { this._u[l.slot] = a; this._u[l.slot + 1] = b; } }
    uniform3fv(l, v) { if (l) { this._u[l.slot] = v[0]; this._u[l.slot + 1] = v[1]; this._u[l.slot + 2] = v[2]; } }
    drawArrays() { const c = this.canvas; c._sync(); N.glDraw(c._id, this._frag, this._u, c._w, c._h); }
    getExtension() { return null; } getParameter() { return 0; } pixelStorei() {} clearColor() {} clear() {} readPixels() {}
  }

  // ---- canvas ----
  class CanvasEl {
    constructor(w, h) { this._w = Math.max(0, +w | 0); this._h = Math.max(0, +h | 0); this._id = ++CANVAS_ID; this._dirty = true; this._ctx2 = null; this._gl = null; this.style = {}; if (reg) reg.register(this, this._id); }
    get width() { return this._w; } set width(v) { v = Math.max(0, +v | 0); this._w = v; this._resized(); }
    get height() { return this._h; } set height(v) { v = Math.max(0, +v | 0); this._h = v; this._resized(); }
    get offsetWidth() { return this._w; } get offsetHeight() { return this._h; } get clientWidth() { return this._w; } get clientHeight() { return this._h; }
    _resized() { this._dirty = true; if (this._ctx2) { this._ctx2._n = 0; this._ctx2._strs = []; this._ctx2._smap = new Map(); this._ctx2._stack.length = 0; this._ctx2._reset(); dirty.delete(this); } }
    _sync() { if (this._dirty) { this._dirty = false; N.canvasResize(this._id, this._w, this._h); } }
    _clearNative() { this._dirty = true; }
    getContext(kind) {
      if (kind === '2d') { if (!this._ctx2) this._ctx2 = new Ctx2D(this); return this._ctx2; }
      if (kind === 'webgl' || kind === 'experimental-webgl') { if (!this._gl) this._gl = new GLStub(this); return this._gl; }
      return null;
    }
    getBoundingClientRect() { return { x: 0, y: 0, left: 0, top: 0, right: this._w, bottom: this._h, width: this._w, height: this._h }; }
    toDataURL() { return ''; } toBlob(cb) { if (cb) cb(null); } addEventListener() {} removeEventListener() {} setAttribute() {} getAttribute() { return null; }
    transferToImageBitmap() { return this; } captureStream() { return null; }
  }
  class OffscreenCanvasEl extends CanvasEl { convertToBlob() { return Promise.resolve(null); } }
  G.OffscreenCanvas = OffscreenCanvasEl; G.HTMLCanvasElement = CanvasEl;
  G.CanvasRenderingContext2D = Ctx2D; G.CanvasGradient = CanvasGradient; G.CanvasPattern = CanvasPattern;

  // ---- Path2D: SVG path data, parsed natively when drawn ----
  const rd = (x) => (Math.round(x * 1000) / 1000);
  class Path2D {
    constructor(d) { this.d = d instanceof Path2D ? d.d : (typeof d === 'string' ? d : ''); }
    addPath(p) { this.d += ' ' + p.d; }
    moveTo(x, y) { this.d += ` M${rd(x)} ${rd(y)}`; } lineTo(x, y) { this.d += ` L${rd(x)} ${rd(y)}`; } closePath() { this.d += ' Z'; }
    bezierCurveTo(a, b, c, d, e, g) { this.d += ` C${rd(a)} ${rd(b)} ${rd(c)} ${rd(d)} ${rd(e)} ${rd(g)}`; } quadraticCurveTo(a, b, c, d) { this.d += ` Q${rd(a)} ${rd(b)} ${rd(c)} ${rd(d)}`; }
    rect(x, y, w, h) { this.d += ` M${rd(x)} ${rd(y)} h${rd(w)} v${rd(h)} h${rd(-w)} Z`; }
    roundRect(x, y, w, h, r) {
      r = Math.max(0, Math.min(Array.isArray(r) ? (+r[0] || 0) : (+r || 0), Math.abs(w) / 2, Math.abs(h) / 2));
      this.d += ` M${rd(x + r)} ${rd(y)} L${rd(x + w - r)} ${rd(y)} Q${rd(x + w)} ${rd(y)} ${rd(x + w)} ${rd(y + r)} L${rd(x + w)} ${rd(y + h - r)} Q${rd(x + w)} ${rd(y + h)} ${rd(x + w - r)} ${rd(y + h)} L${rd(x + r)} ${rd(y + h)} Q${rd(x)} ${rd(y + h)} ${rd(x)} ${rd(y + h - r)} L${rd(x)} ${rd(y + r)} Q${rd(x)} ${rd(y)} ${rd(x + r)} ${rd(y)} Z`;
    }
    ellipse(x, y, rx, ry, rot, a0, a1, ccw) {
      const cr = Math.cos(rot || 0), sr = Math.sin(rot || 0), P = (a) => [x + rx * Math.cos(a) * cr - ry * Math.sin(a) * sr, y + rx * Math.cos(a) * sr + ry * Math.sin(a) * cr];
      const TWO = Math.PI * 2; let sweep = a1 - a0; if (!ccw && sweep > TWO) sweep = TWO; if (ccw && sweep < -TWO) sweep = -TWO;
      if (!ccw && sweep < 0) sweep = ((sweep % TWO) + TWO) % TWO; if (ccw && sweep > 0) sweep = -((((-sweep) % TWO) + TWO) % TWO);
      const steps = Math.max(2, Math.ceil(Math.abs(sweep) / (Math.PI / 2))); const p0 = P(a0); this.d += (this.d ? ' L' : ' M') + rd(p0[0]) + ' ' + rd(p0[1]);
      for (let i = 1; i <= steps; i++) { const p = P(a0 + sweep * i / steps); this.d += ` A${rd(rx)} ${rd(ry)} ${rd((rot || 0) * 180 / Math.PI)} 0 ${sweep > 0 ? 1 : 0} ${rd(p[0])} ${rd(p[1])}`; }
    }
    arc(x, y, r, a0, a1, ccw) { this.ellipse(x, y, r, r, 0, a0, a1, ccw); }
  }
  G.Path2D = Path2D;

  // ---- images: loaded by native, announced back ----
  const IMGS = new Map(); let IMG_ID = 0;
  class ImageEl {
    constructor(w, h) { this._id = ++IMG_ID; this.complete = false; this.naturalWidth = 0; this.naturalHeight = 0; this.onload = null; this.onerror = null; this._src = ''; this.crossOrigin = null; this._l = {}; }
    get width() { return this.naturalWidth; } set width(v) {} get height() { return this.naturalHeight; } set height(v) {}
    get src() { return this._src; } set src(v) { this._src = String(v); this.complete = false; IMGS.set(this._id, this); N.imageLoad(this._id, this._src); }
    addEventListener(t, fn) { (this._l[t] = this._l[t] || []).push(fn); } removeEventListener() {}
    decode() { return this.complete ? Promise.resolve() : new Promise((ok, no) => { const p = this.onload, q = this.onerror; this.onload = () => { if (p) p(); ok(); }; this.onerror = () => { if (q) q(); no(new Error('decode')); }; }); }
  }
  G.Image = ImageEl; G.HTMLImageElement = ImageEl;
  G.__imgDone = (id, ok, w, h) => {
    const im = IMGS.get(id); if (!im) return; IMGS.delete(id); im.complete = true;
    if (ok) { im.naturalWidth = w; im.naturalHeight = h; } else { im.naturalWidth = 0; im.naturalHeight = 0; }
    const cb = ok ? im.onload : im.onerror; try { if (cb) cb.call(im, {}); (im._l[ok ? 'load' : 'error'] || []).forEach((fn) => fn.call(im, {})); } catch (e) { N.log(2, 'img: ' + e); }
  };

  // ---- fetch, resolved natively against the gallery ----
  const FET = new Map(); let FID = 0;
  G.fetch = (url, opts) => new Promise((ok, no) => {
    const id = ++FID; FET.set(id, { ok, no });
    N.fetch(id, String(url), (opts && opts.method) || 'GET', (opts && typeof opts.body === 'string') ? opts.body : '');
  });
  G.__fetchDone = (id, status, text) => {
    const r = FET.get(id); if (!r) return; FET.delete(id);
    if (status <= 0) { r.no(new TypeError('Network request failed')); return; }
    r.ok({ ok: status >= 200 && status < 300, status, url: '', text: () => Promise.resolve(text), json: () => Promise.resolve().then(() => JSON.parse(text)), headers: { get: () => null } });
  };

  // ---- DOMParser: enough SVG for his comps (svg viewBox, path d, stroke-width) ----
  const attrs = (s) => { const o = {}; const re = /([\w:.-]+)\s*=\s*("([^"]*)"|'([^']*)')/g; let m; while ((m = re.exec(s))) o[m[1]] = m[3] !== undefined ? m[3] : m[4]; return o; };
  const el = (a) => ({ getAttribute: (k) => (k in a ? a[k] : null), hasAttribute: (k) => k in a });
  G.DOMParser = class { parseFromString(txt) {
    const sm = /<svg\b([^>]*)>/i.exec(txt); const svg = sm ? el(attrs(sm[1])) : null; const paths = []; const re = /<path\b([^>]*?)\/?>/gi; let m; while ((m = re.exec(txt))) paths.push(el(attrs(m[1])));
    return { querySelector: (q) => (q === 'svg' ? svg : q === 'path' ? paths[0] || null : null), querySelectorAll: (q) => (q === 'path' ? paths : []) };
  } };

  // ---- document: just what the bundles touch ----
  const fonts = { load: () => Promise.resolve([]), check: (spec) => { const m = /"?([A-Za-z][\w ]*)"?\s*$/.exec(String(spec)); return m ? !!N.hasFont(m[1]) : false; }, ready: Promise.resolve(), add() {}, addEventListener() {} };
  G.document = {
    fonts, currentScript: { src: '' }, body: { appendChild() {}, style: {} }, head: { appendChild() {} }, documentElement: { style: {}, clientWidth: 390, clientHeight: 844 },
    createElement(tag) { tag = String(tag).toLowerCase(); if (tag === 'canvas') return new CanvasEl(300, 150); if (tag === 'img') return new ImageEl(); return { style: {}, setAttribute() {}, appendChild() {}, addEventListener() {} }; },
    createElementNS(ns, tag) { return this.createElement(tag); }, getElementById() { return null; }, querySelector() { return null; }, querySelectorAll() { return []; }, addEventListener() {}, removeEventListener() {}, hidden: false,
  };
  G.addEventListener = G.removeEventListener = () => {}; G.dispatchEvent = () => true; G.matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {} });
  G.CustomEvent = class { constructor(t, o) { this.type = t; this.detail = o && o.detail; } }; G.Event = G.CustomEvent;

  // ---- the harness: the exact make -> warm -> draw loop CurateDeck's LivePieceCanvas and /pieces/embed run ----
  const INST = new Map(); let HID = 0;
  const allPieces = () => [].concat(G.PL_PIECES || [], G.PL_ARCHIVE || []);
  G.__listPieces = () => {
    const live = new Set((G.PL_PIECES || []).map((p) => p.id)); const seen = new Set(); const out = []; const ai = G.PL_AI_IDS || new Set(); const H2X = new Set(['dir-01', 'dir-02']);
    // the gallery's own sets (app/curves/page.tsx): wave-one by prefix, then wave-two, then jarvis-crafted, then the rest of the archive; canon is the live remainder
    const setOf = (p) => (p.id.startsWith('w1-') ? 'wave-one' : (p.id.startsWith('h2-') || H2X.has(p.id)) ? 'wave-two' : live.has(p.id) ? 'canon' : ai.has(p.id) ? 'jarvis-crafted' : 'curve-archive');
    for (const p of allPieces()) { if (seen.has(p.id)) continue; seen.add(p.id); out.push({ id: p.id, name: p.name || p.id, sub: p.sub || '', tags: p.tags || [], pal: p.pal || null, comp: p.needsComp || null, warm: p.warm == null ? 60 : p.warm, live: live.has(p.id), set: setOf(p) }); }
    return JSON.stringify(out);
  };
  // pxW/pxH: bitmap size; dpr: bitmap pixels per css px. Returns the handle and the native canvas id.
  G.__newInstance = (id, pxW, pxH, dpr) => {
    const p = allPieces().find((q) => q.id === id); if (!p) return JSON.stringify({ error: 'missing' });
    const cv = new CanvasEl(pxW, pxH), ctx = cv.getContext('2d'); ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const w = pxW / dpr, h = pxH / dpr; let st;
    try { st = p.make(w, h); } catch (e) { N.log(2, 'make ' + id + ': ' + e); return JSON.stringify({ error: 'make: ' + e }); }
    if (st && p.pal) st.pal = p.pal;
    const hd = ++HID; INST.set(hd, { p, st, cv, ctx, w, h, dpr, frame: 0, warm: p.warm == null ? 60 : p.warm, warmed: 0, errors: 0 });
    cv._sync();
    return JSON.stringify({ handle: hd, canvas: cv._id, comp: p.needsComp || null, w, h, warm: p.warm == null ? 60 : p.warm });
  };
  G.__warm = (hd, n) => { const s = INST.get(hd); if (!s) return 0; let k = 0; while (k < n && s.warmed < s.warm) { try { s.p.draw(s.ctx, s.st, s.w, s.h, s.frame++); } catch (e) { if (s.errors++ < 3) N.log(2, "warm " + s.p.id + ": " + ((e && e.stack) || e)); } s.warmed++; k++; } G.__flushAll(); return s.warm - s.warmed; };
  G.__draw = (hd, frame) => {
    const s = INST.get(hd); if (!s) return -1; if (frame == null || frame < 0) frame = s.frame++; else s.frame = frame + 1;
    try { s.p.draw(s.ctx, s.st, s.w, s.h, frame); } catch (e) { if (s.errors++ < 3) N.log(2, 'draw ' + s.p.id + ': ' + e); }
    G.__flushAll(); return s.errors;
  };
  // Draw through a transform (the VJ deck's zoom, tilt and breathe), then the warm wash and the beat border, exactly as VJEngine does it.
  G.__drawXf = (hd, frame, zoom, angleDeg, alpha, warm, beat) => {
    const s = INST.get(hd); if (!s) return -1; const ctx = s.ctx; s.frame = Math.max(s.frame, frame + 1);
    ctx.save(); ctx.globalAlpha = alpha; const cx = s.w / 2, cy = s.h / 2; ctx.translate(cx, cy); ctx.scale(zoom, zoom); if (angleDeg) ctx.rotate(angleDeg * Math.PI / 180); ctx.translate(-cx, -cy);
    try { s.p.draw(ctx, s.st, s.w, s.h, frame); } catch (e) { if (s.errors++ < 3) N.log(2, 'draw ' + s.p.id + ': ' + e); }
    ctx.restore();
    if (warm > 0.005) { ctx.save(); ctx.globalCompositeOperation = 'overlay'; ctx.globalAlpha = Math.min(warm, 0.45); ctx.fillStyle = 'rgba(201,168,76,1)'; ctx.fillRect(0, 0, s.w, s.h); ctx.restore(); }
    if (beat) { ctx.save(); const g = ctx.createLinearGradient(0, 0, 0, s.h); g.addColorStop(0, 'rgba(201,168,76,0.65)'); g.addColorStop(0.5, 'rgba(201,168,76,0)'); g.addColorStop(1, 'rgba(201,168,76,0.65)'); ctx.strokeStyle = g; ctx.lineWidth = 4; ctx.strokeRect(2, 2, s.w - 4, s.h - 4); ctx.restore(); }
    G.__flushAll(); return s.errors;
  };
  G.__resizeInstance = (hd, pxW, pxH, dpr) => {
    const s = INST.get(hd); if (!s) return; s.cv.width = pxW; s.cv.height = pxH; s.ctx.setTransform(dpr, 0, 0, dpr, 0, 0); s.dpr = dpr; s.w = pxW / dpr; s.h = pxH / dpr;
    try { s.st = s.p.make(s.w, s.h); if (s.st && s.p.pal) s.st.pal = s.p.pal; } catch (e) {} s.warmed = 0; s.cv._sync();
  };
  G.__freeInstance = (hd) => { INST.delete(hd); };
  G.__loadComp = (n, cb) => { try { Promise.resolve(G.PL_loadComp(String(n).padStart(2, '0'))).then(() => cb(1), () => cb(0)); } catch (e) { cb(0); } };
  G.__flushAll = () => { for (const c of Array.from(dirty)) { if (c._ctx2) c._ctx2._flush(); else dirty.delete(c); } };
  // Forge: run source that registers a piece, return the one it added (the wrapper ForgePreview injects, in the same scope).
  G.__forgeRun = (code) => {
    try {
      const before = (typeof PIECES !== 'undefined') ? PIECES.length : 0;
      (0, eval)(code);
      if (typeof PIECES !== 'undefined' && PIECES.length > before) { const p = PIECES[PIECES.length - 1]; G.PL_ARCHIVE = (G.PL_ARCHIVE || []).filter((q) => q.id !== p.id).concat([p]); return JSON.stringify({ id: p.id, name: p.name || p.id }); }
      return JSON.stringify({ error: 'The code did not register a piece({...}).' });
    } catch (e) { return JSON.stringify({ error: String((e && e.message) || e) }); }
  };
})(globalThis);
