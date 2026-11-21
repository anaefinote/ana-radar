// glmaze.js — EFINOTE's maze balls on the GPU (WebGL), from the user's per-pixel sphere sketches
// (Processing 1.5.1): the same sphere set-up (orthographic, n = (dx, dy, sqrt(R^2 - d^2)) / R), the same
// materials (K: Volcanic Agate, O: Emerald Vein, U: Liquid Mercury), the same light / specular / Fresnel /
// grain, and the same weathering ideas: GOOEY mode B (material mask, cavity AO, Worley cracks on the warped
// domain, rim glow) for the past, a clean emerald glass for the present, and ETCH (bevel glow) for the future.
// The mask is the day's timeline maze: one ridge per hour round the core, doors where notifications are,
// mirrored walls (the sketch sends each day's doors / walls as a 256 x 32 texture: red = door, green = wall).
//
// Made fast:
//  1. BAKED SKIN. The expensive part (the noise layers, the Worley cracks) never changes, so each material is
//     computed once into a 2048 x 1024 texture wrapped round the ball (round = the minute angle, down = the
//     angle from the core) and read back per pixel. Only the maze (cheap, and sharp at any zoom) is per pixel.
//  2. NO COPY. This canvas sits BEHIND the sketch's canvas (the sketch clears to see-through on Archive and
//     draws its header, beads and bar on top), so nothing is copied back into the sketch each frame.
//  3. DRAW ON CHANGE. If nothing moved since the last frame, nothing is drawn: the last picture stays up.
//  4. SMALL BOXES. Each ball draws only the square round its lens, not the whole screen.
//  5. ADAPTIVE RESOLUTION. While a big view moves and frames run slow, it draws at a lower resolution and
//     scales up; as soon as it stops it draws once more at full resolution.

var GLMaze = (function () {
  var api = { ok: false };

  var VS = [
    'attribute vec2 aPos;',
    'uniform vec4 uBox;',          // clip-space x0, y0, x1, y1
    'varying vec2 vUV;',
    'void main() {',
    '  vUV = aPos * 0.5 + 0.5;',
    '  gl_Position = vec4(mix(uBox.xy, uBox.zw, vUV), 0.0, 1.0);',
    '}'
  ].join('\n');

  var COMMON = [
    '#ifdef GL_OES_standard_derivatives',
    '#extension GL_OES_standard_derivatives : enable',
    '#endif',
    'precision highp float;',
    'const float PI = 3.14159265;',
    'const float TP = 6.28318531;',
    'float fc(float turns) { return cos(TP * turns); }'
  ].join('\n');

  // ---- the bake: one material's colour (rgb) and crack darkening (a), round x down the angle from the core
  var BAKE_FS = COMMON + '\n' + [
    'uniform vec2 uSize;',
    'uniform float uMat;',
    'uniform float uGoo;',
    'float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }',
    'float vn(vec3 x) {',
    '  vec3 i = floor(x), f = fract(x); f = f * f * (3.0 - 2.0 * f);',
    '  return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),',
    '             mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);',
    '}',
    // Processing's noise(): 4 octaves, falloff 0.5, about 0..1
    'float noise(vec3 p) { float s = 0.0, a = 0.5, t = 0.0; for (int i = 0; i < 4; i++) { s += vn(p) * a; t += a; p *= 2.0; a *= 0.5; } return s / t; }',
    'float hashA(vec2 c) { return fract(sin(c.x * 127.1 + c.y * 311.7) * 43758.5453); }',
    'float hashB(vec2 c) { return fract(sin(c.x * 269.5 + c.y * 183.3) * 43758.5453); }',
    'vec2 worley2D(vec2 p, float sc) {',
    '  vec2 x = p * sc, xi = floor(x); float f1 = 999.0, f2 = 999.0;',
    '  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {',
    '    vec2 c = xi + vec2(float(i), float(j));',
    '    vec2 pt = c + vec2(hashA(c), hashB(c));',
    '    float d = length(pt - x);',
    '    if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) { f2 = d; }',
    '  }',
    '  return vec2(f1, f2);',
    '}',
    'vec2 warpDomain(vec2 e) { float r = length(e); float a = atan(e.y, e.x) + 2.4 * r; return vec2(r * cos(a), r * sin(a)); }',
    'void main() {',
    '  float phi = gl_FragCoord.x / uSize.x * TP;',
    '  float rho = gl_FragCoord.y / uSize.y * PI;',
    '  vec3 p = vec3(sin(rho) * sin(phi), -sin(rho) * cos(phi), cos(rho));',   // as mazeH: phi = atan(x, -y)
    '  float rx = p.x, ry = p.y, rz = p.z;',
    '  vec3 col; float crack = 1.0;',
    '  if (uMat < 0.5) {',                                           // K: Volcanic Agate (the past)
    '    float nK1 = noise(p * 3.0);',
    '    float nK2 = noise(p * 6.0 + nK1 * 3.0);',
    '    float bandK = sin(nK2 * 18.0 + rz * 4.0) * 0.5 + 0.5;',
    '    float ph = bandK * 0.5 + nK1 * 0.4;',
    '    col = vec3(0.65 + 0.35 * fc(ph), 0.25 + 0.25 * fc(ph + 0.25), 0.10 + 0.15 * fc(ph + 0.50));',
    '    vec2 w = worley2D(warpDomain(vec2(rx, ry)), 8.0);',            // GOOEY B cracks
    '    float crackW = mix(0.02, 0.09, uGoo);',
    '    crack = 1.0 - (1.0 - smoothstep(0.0, crackW, w.y - w.x)) * 0.8;',
    '  } else if (uMat < 1.5) {',                                    // O: Emerald Vein (the present)
    '    float nO1 = noise(vec3(rx * 3.0 + 2.0, ry * 3.0, rz * 3.0));',
    '    float nO2 = noise(vec3(rx * 4.0 + nO1 * 2.5, ry * 4.0 + nO1 * 2.5, rz * 4.0));',
    '    float veinO = sin((rx - ry + nO2 * 2.0) * 10.0) * 0.5 + 0.5;',
    '    float ph = veinO * 0.5 + (1.0 - rz) * 0.5;',
    '    col = vec3(0.10 + 0.25 * fc(ph + 0.60), 0.55 + 0.40 * fc(ph + 0.20), 0.30 + 0.30 * fc(ph + 0.40));',
    '  } else {',                                                    // U: Liquid Mercury (the future)
    '    float dU1 = distance(vec2(rx, ry), vec2(-0.25, 0.2));',
    '    float dU2 = distance(vec2(rx, ry), vec2(0.25, -0.25));',
    '    float ripU = sin(dU1 * 22.0) + cos(dU2 * 18.0) + noise(vec3(rx * 4.0, ry * 4.0, 0.0)) * 2.0;',
    '    float ph = (ripU * 0.25 + 0.5) * 0.4 + (1.0 - rz) * 0.6;',
    '    col = vec3(0.65 + 0.30 * fc(ph), 0.70 + 0.25 * fc(ph + 0.3), 0.80 + 0.20 * fc(ph + 0.6));',
    '  }',
    '  gl_FragColor = vec4(clamp(col, 0.0, 1.0), crack);',
    '}'
  ].join('\n');

  // ---- a ball, in its lens
  var BALL_FS = COMMON + '\n' + [
    'uniform vec2 uCanvas;',
    'uniform vec2 uC;',
    'uniform float uR;',           // the sphere's radius on screen
    'uniform float uClip;',        // the lens: nothing outside this radius from uC
    'uniform mat3 uRot;',
    'uniform float uMat;',
    'uniform float uGoo;',
    'uniform float uDark;',
    'uniform float uAlpha;',
    'uniform float uSee;',
    'uniform sampler2D uDoors;',
    'uniform sampler2D uSkin;',
    'const float NR = 27.0;',      // ridges (Maze.pde MZ_RIDGES)
    'float mazeH(vec3 p) {',
    '  float rho = acos(clamp(p.z, -1.0, 1.0));',
    '  float phi = atan(p.x, -p.y); if (phi < 0.0) phi += TP;',
    '  float w = 1.0 + 0.10 * cos(phi) + 0.07 * cos(2.0 * phi);',
    '  float kf = rho * (NR + 1.0) / (PI * 0.97 * w) - 1.0;',
    '  float k = floor(kf + 0.5);',
    '  float f = abs(kf - k) / 0.36;',
    '  float tube = sqrt(max(0.0, 1.0 - f * f));',
    '  float u = phi / TP;',
    '  if (k < 0.0 || k > NR - 1.0) tube = 0.0;',
    '  else tube *= 1.0 - texture2D(uDoors, vec2(u, (k + 0.5) / 32.0)).r;',
    '  float kc = floor(kf);',
    '  float wall = 0.0;',
    '  if (kc >= 0.0 && kc <= NR - 2.0) wall = sqrt(texture2D(uDoors, vec2(u, (kc + 0.5) / 32.0)).g);',
    '  return max(tube, wall);',
    '}',
    'void main() {',
    '  vec2 frag = vec2(gl_FragCoord.x, uCanvas.y - gl_FragCoord.y);',
    '  vec2 d = frag - uC;',
    '  float d2 = dot(d, d), dl = sqrt(d2);',
    '  float edge = clamp(uR - dl + 0.5, 0.0, 1.0) * clamp(uClip - dl + 0.5, 0.0, 1.0);',
    '  vec3 n = vec3(d.x, d.y, sqrt(max(uR * uR - d2, 0.0))) / uR;',
    '  vec3 p = normalize(uRot * n);',
    // the baked skin: pick whichever of two wraps has no seam here (so the mipmap level stays right)
    '  float uu = atan(p.x, -p.y) / TP;',
    '  float uA = fract(uu), uB = fract(uu + 0.5) - 0.5;',
    '  float us = uA;',
    '#ifdef GL_OES_standard_derivatives',
    '  us = fwidth(uA) <= fwidth(uB) + 0.000001 ? uA : uB;',
    '#endif',
    '  float rho = acos(clamp(p.z, -1.0, 1.0));',
    '  vec4 sk = texture2D(uSkin, vec2(us, rho / PI));',
    '  if (edge <= 0.0) { gl_FragColor = vec4(0.0); return; }',
    '  vec3 col = sk.rgb;',
    '  float crackDarken = sk.a;',
    '  vec3 L = vec3(0.35, -0.55, 0.75); float specPower = 35.0, specStrength = 1.3, fresnelPow = 2.2, fresnelAmt = 0.5;',
    '  if (uMat < 0.5) { specPower = 95.0; specStrength = 1.7; }',
    '  else if (uMat < 1.5) { specPower = 65.0; specStrength = 1.5; }',
    '  else { L = vec3(0.2, -0.7, 0.7); specPower = 150.0; specStrength = 3.0; fresnelPow = 1.4; }',
    // the maze as the weathering mask, and its slope as the normal's bump (tangent frame, as in the 2nd sketch)
    '  float h = mazeH(p);',
    '  vec3 up = abs(p.z) > 0.995 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);',
    '  vec3 tA = normalize(cross(up, p));',
    '  vec3 bA = cross(p, tA);',
    '  float dd = 0.0035;',
    '  float gT = (mazeH(normalize(p + dd * tA)) - h) / dd;',
    '  float gB = (mazeH(normalize(p + dd * bA)) - h) / dd;',
    '  vec3 pObj = -(gT * tA + gB * bA) * 0.03;',
    '  n = normalize(n + pObj * uRot);',
    '  float thr = 0.22;',
    '  float band = mix(0.03, 0.30, uGoo);',
    '#ifdef GL_OES_standard_derivatives',
    '  band = max(band, fwidth(h) * 0.8);',
    '#endif',
    '  float materialMask = smoothstep(thr - band, thr + band, h);',
    '  float cavityAO = mix(mix(0.55, 0.25, uDark), 1.0, h);',
    '  L = normalize(L);',
    '  float dotNL = max(0.0, dot(n, L));',
    '  vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));',
    '  float spec = pow(max(0.0, dot(n, H)), specPower);',
    '  float fresnel = pow(1.0 - n.z, fresnelPow);',
    '  float intensity = (0.18 + 0.82 * dotNL) * cavityAO;',
    '  vec3 fin = (col * intensity + spec * specStrength) * (1.0 - fresnel * fresnelAmt);',
    '  float rimGlow;',
    '  if (uMat < 0.5) {',                                           // GOOEY mode B: rim glow (cracks are baked)
    '    float rim = clamp(1.0 - abs(h - thr) / mix(0.035, 0.14, uGoo), 0.0, 1.0);',
    '    rimGlow = pow(rim, mix(4.0, 1.8, uGoo));',
    '  } else if (uMat > 1.5) {',                                    // ETCH: a crisp bevel on every edge
    '    float bevel = clamp(1.0 - abs(h - thr) / 0.05, 0.0, 1.0);',
    '    rimGlow = pow(bevel, 2.2) * 0.7;',
    '  } else {',                                                    // emerald glass: a light rim
    '    float rim = clamp(1.0 - abs(h - thr) / 0.08, 0.0, 1.0);',
    '    rimGlow = pow(rim, 3.0) * 0.35;',
    '  }',
    '  fin *= crackDarken;',
    '  vec3 sub = (vec3(mix(0.10, 0.02, uDark)) + col * mix(0.45, 0.12, uDark)) * cavityAO;',
    '  vec3 outc = mix(sub, fin, materialMask);',
    '  outc += rimGlow * (uMat > 1.5 ? vec3(0.6) : uMat < 0.5 ? vec3(0.55, 0.50, 0.40) : vec3(0.25, 0.6, 0.4));',
    '  outc += vec3(1.0, 0.55, 0.2) * exp(-rho * rho * 90.0) * 1.4;',  // the core
    '  float grain = (fract(sin(dot(floor(frag), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.04;',
    '  outc = clamp(outc + grain, 0.0, 1.0);',
    '  float a = mix(1.0 - uSee, 1.0, materialMask) * edge * uAlpha;',
    '  gl_FragColor = vec4(outc * a, a);',
    '}'
  ].join('\n');

  // ---- copy a texture to the screen (the background, and the low-resolution frame scaled up)
  var BLIT_FS = [
    'precision mediump float;',
    'uniform sampler2D uTex;',
    'uniform float uFlip;',
    'varying vec2 vUV;',
    'void main() { gl_FragColor = texture2D(uTex, vec2(vUV.x, mix(vUV.y, 1.0 - vUV.y, uFlip))); }'
  ].join('\n');

  var cv = null, gl = null, P = {}, buf = null, W = 0, H = 0;
  var doorTex = {}, doorVer = {}, skin = [null, null, null], skinGoo = [-1, -1, -1], SK_W = 2048, SK_H = 1024;
  var bgTex = null, bgVer = 0, lowFbo = null, lowTex = null, lowW = 0, lowH = 0;
  var layers = [], lastKey = '', lastFull = true, lastMoveAt = 0, lastEnd = 0, frameMs = 16, scale = 1, shown = false;

  function shader(type, src) {
    var s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  function program(fs, names) {
    var p = gl.createProgram();
    gl.attachShader(p, shader(gl.VERTEX_SHADER, VS));
    gl.attachShader(p, shader(gl.FRAGMENT_SHADER, fs));
    gl.bindAttribLocation(p, 0, 'aPos');
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    var o = { p: p, u: {} };
    names.concat(['uBox']).forEach(function (n) { o.u[n] = gl.getUniformLocation(p, n); });
    return o;
  }
  function box(o, x0, y0, x1, y1, w, h) {   // pixels (y down) -> clip space
    gl.uniform4f(o.u.uBox, x0 / w * 2 - 1, 1 - y1 / h * 2, x1 / w * 2 - 1, 1 - y0 / h * 2);
  }
  function texture(w, h, mip) {
    var t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, mip ? gl.REPEAT : gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, mip ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    return t;
  }

  try {
    cv = document.createElement('canvas');
    cv.id = 'glmaze';
    cv.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;z-index:0;pointer-events:none;display:none;';
    gl = cv.getContext('webgl', { premultipliedAlpha: true, alpha: true, antialias: false, preserveDrawingBuffer: false });
    if (gl) {
      gl.getExtension('OES_standard_derivatives');
      P.bake = program(BAKE_FS, ['uSize', 'uMat', 'uGoo']);
      P.ball = program(BALL_FS, ['uCanvas', 'uC', 'uR', 'uClip', 'uRot', 'uMat', 'uGoo', 'uDark', 'uAlpha', 'uSee', 'uDoors', 'uSkin']);
      P.blit = program(BLIT_FS, ['uTex', 'uFlip']);
      buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
      if (gl.getParameter(gl.MAX_TEXTURE_SIZE) < 2048) { SK_W = 1024; SK_H = 512; }
      api.ok = true;
      var put = function () { if (document.body) document.body.insertBefore(cv, document.body.firstChild); };
      if (document.body) put(); else document.addEventListener('DOMContentLoaded', put);
    }
  } catch (e) {
    api.ok = false;
    api.error = String(e);
  }

  // bake one material's skin (once; again only if its gooeyness changes)
  function bake(mat, goo) {
    if (skin[mat] && skinGoo[mat] === goo) return;
    if (!skin[mat]) skin[mat] = texture(SK_W, SK_H, true);
    skinGoo[mat] = goo;
    var fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, skin[mat], 0);
    gl.viewport(0, 0, SK_W, SK_H);
    gl.disable(gl.BLEND);
    gl.useProgram(P.bake.p);
    gl.uniform4f(P.bake.u.uBox, -1, -1, 1, 1);
    gl.uniform2f(P.bake.u.uSize, SK_W, SK_H);
    gl.uniform1f(P.bake.u.uMat, mat);
    gl.uniform1f(P.bake.u.uGoo, goo);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.deleteFramebuffer(fb);
    gl.bindTexture(gl.TEXTURE_2D, skin[mat]);
    gl.generateMipmap(gl.TEXTURE_2D);
  }

  // a shell's doors / walls (the sketch's 256 x 32 PGraphics), kept per slot
  api.doors = function (slot, pg) {
    if (!api.ok || !pg || !pg.externals) return;
    var t = doorTex[slot];
    if (!t) {
      t = doorTex[slot] = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    }
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, pg.externals.canvas);
    doorVer[slot] = (doorVer[slot] || 0) + 1;
  };

  // the screen's background (the sketch's flatBg), drawn under the balls
  api.bg = function (pg) {
    if (!api.ok || !pg || !pg.externals) return;
    if (!bgTex) bgTex = texture(1, 1, false);
    gl.bindTexture(gl.TEXTURE_2D, bgTex);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, pg.externals.canvas);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    bgVer++;
  };

  api.begin = function (w, h) {
    if (!api.ok) return;
    if (w !== W || h !== H) { cv.width = W = w; cv.height = H = h; lastKey = ''; }
    layers.length = 0;
  };

  // one ball. a = [cx, cy, R, rot0..rot8, mat, goo, dark, alpha, see, clip]  (canvas pixels)
  api.layer = function (slot, a) {
    if (!api.ok || !doorTex[slot]) return;
    var l = [slot];
    for (var i = 0; i < 18; i++) l.push(+a[i]);
    layers.push(l);
  };

  function drawAll(s, w, h) {
    gl.viewport(0, 0, w, h);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (bgTex) {
      gl.disable(gl.BLEND);
      gl.useProgram(P.blit.p);
      gl.uniform4f(P.blit.u.uBox, -1, -1, 1, 1);
      gl.uniform1f(P.blit.u.uFlip, 1);
      gl.uniform1i(P.blit.u.uTex, 0);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, bgTex);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    var o = P.ball;
    gl.useProgram(o.p);
    gl.uniform2f(o.u.uCanvas, w, h);
    gl.uniform1i(o.u.uDoors, 0);
    gl.uniform1i(o.u.uSkin, 1);
    for (var i = 0; i < layers.length; i++) {
      var l = layers[i], cx = l[1] * s, cy = l[2] * s, R = l[3] * s, clip = l[18] * s;
      var e = Math.min(R, clip) + 2;
      box(o, Math.max(0, cx - e), Math.max(0, cy - e), Math.min(w, cx + e), Math.min(h, cy + e), w, h);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, doorTex[l[0]]);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, skin[Math.round(l[13])]);
      gl.uniform2f(o.u.uC, cx, cy);
      gl.uniform1f(o.u.uR, R);
      gl.uniform1f(o.u.uClip, clip);
      gl.uniformMatrix3fv(o.u.uRot, false, new Float32Array(l.slice(4, 13)));
      gl.uniform1f(o.u.uMat, l[13]);
      gl.uniform1f(o.u.uGoo, l[14]);
      gl.uniform1f(o.u.uDark, l[15]);
      gl.uniform1f(o.u.uAlpha, l[16]);
      gl.uniform1f(o.u.uSee, l[17]);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    gl.activeTexture(gl.TEXTURE0);
  }

  // draw the frame, if anything changed
  api.end = function () {
    if (!api.ok) return;
    if (!shown) { cv.style.display = 'block'; shown = true; lastKey = ''; }
    var now = performance.now();
    if (lastEnd) frameMs = frameMs * 0.9 + Math.min(100, now - lastEnd) * 0.1;
    lastEnd = now;
    for (var i = 0; i < layers.length; i++) bake(Math.round(layers[i][13]), layers[i][14]);
    var key = W + 'x' + H + ':' + bgVer;
    var pix = 0;
    for (i = 0; i < layers.length; i++) {
      var l = layers[i];
      key += '|' + l[0] + ',' + (doorVer[l[0]] || 0);
      for (var j = 1; j < 19; j++) key += ',' + Math.round(l[j] * 1000);
      var e = Math.min(l[3], l[18]);
      pix += Math.PI * e * e;
    }
    if (key === lastKey) {
      // still: if the last frame was drawn small, draw it once more at full resolution
      if (lastFull || now - lastMoveAt < 120) return;
      drawAll(1, W, H);
      lastFull = true;
      return;
    }
    lastKey = key;
    lastMoveAt = now;
    // moving: a big view on a slow GPU draws at a lower resolution while it moves
    if (pix > W * H * 0.35) {
      if (frameMs > 24) scale = Math.max(0.5, scale - 0.05);
      else if (frameMs < 17) scale = Math.min(1, scale + 0.02);
    }
    else scale = 1;
    if (scale > 0.97) { drawAll(1, W, H); lastFull = true; return; }
    var lw = Math.max(1, Math.round(W * scale)), lh = Math.max(1, Math.round(H * scale));
    if (!lowTex || lw !== lowW || lh !== lowH) {
      if (lowTex) gl.deleteTexture(lowTex);
      if (!lowFbo) lowFbo = gl.createFramebuffer();
      lowTex = texture(lw, lh, false);
      lowW = lw; lowH = lh;
      gl.bindFramebuffer(gl.FRAMEBUFFER, lowFbo);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, lowTex, 0);
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, lowFbo);
    drawAll(lw / W, lw, lh);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, W, H);
    gl.disable(gl.BLEND);
    gl.useProgram(P.blit.p);
    gl.uniform4f(P.blit.u.uBox, -1, -1, 1, 1);
    gl.uniform1f(P.blit.u.uFlip, 0);
    gl.uniform1i(P.blit.u.uTex, 0);
    gl.bindTexture(gl.TEXTURE_2D, lowTex);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    lastFull = false;
  };

  // another screen: hide the layer
  api.hide = function () {
    if (!api.ok || !shown) return;
    cv.style.display = 'none';
    shown = false;
  };

  api.stats = function () { return { scale: scale, frameMs: frameMs, skin: SK_W + 'x' + SK_H }; };

  return api;
})();
