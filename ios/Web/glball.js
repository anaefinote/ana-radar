// glball.js — the ANA control ball on the GPU (WebGL), like GLGraphics on the desktop.
//
// The fragment shader below is BallGUI's per-pixel maths from Ball.pde (traceBall / shadePixel and the
// ray-sphere set-up in ballLayout), line for line, with two differences:
//   - every pixel gets the full shading, bump included, every frame (no 2 x 2 draft while moving)
//   - 4 samples per pixel (rotated grid): the edges of the ball and of the panel art are antialiased
// The sketch still builds the panel texture (guiTex) and the skin texture (backTex) and runs everything else;
// this only shades the ball and draws the result into the sketch's canvas.
// If WebGL isn't available, GLBall.ok is false and Ball.pde traces on the CPU as before.

var GLBall = (function () {
  var VS = 'attribute vec2 aPos; void main(){ gl_Position = vec4(aPos, 0.0, 1.0); }';

  var FS = [
    'precision highp float;',
    'uniform sampler2D uFront, uBack;',
    'uniform vec2 uSize;',                       // the ball's square, px
    'uniform float uSr, uFov, uR, uDist;',
    'uniform float uCamX, uCamY, uBrt;',
    'uniform vec4 uPress;',                      // pressed control, texture px (x, y, w, h); w < 0 = none
    'uniform vec3 uL, uH;',
    'uniform vec2 uTex;',                        // texture size (1024, 1024)
    'const float PI = 3.14159265359;',
    'const float TWO_PI = 6.28318530718;',
    'const float HALF_PI = 1.57079632679;',
    'float lum(vec3 c){ return (c.r + c.g + c.b) * 85.0; }',   // 0..255 like guiLum ((r+g+b)/3 in 0..255)
    'vec4 shadeAt(vec2 p) {',
    '  float rr = length(p);',
    '  if (rr > uSr) return vec4(0.0);',
    '  vec3 rd = normalize(vec3(p / uFov, 1.0));',
    '  float b = -uDist * rd.z;',
    '  float disc = max(b * b - (uDist * uDist - uR * uR), 0.0);',
    '  float t = -b - sqrt(disc);',
    '  vec3 hit = rd * t + vec3(0.0, 0.0, -uDist);',
    '  vec3 n = normalize(hit / uR);',
    '  float diff = max(0.0, -dot(n, uL));',
    '  float st0 = dot(n, uH);',
    '  float spec = st0 > 0.0 ? pow(st0, 36.0) : 0.0;',
    '  float rimT = 1.0 + n.z;',
    '  float rim = rimT > 0.0 ? pow(rimT, 2.5) * 0.6 : 0.0;',
    '  vec2 s = hit.xy / uR;',
    '  float sd2 = dot(s, s);',
    '  float g2 = 0.0;',
    '  if (sd2 < 0.98) {',
    '    float sz = sqrt(max(0.0, 1.0 - sd2));',
    '    float gT = -s.x * 0.55 - s.y * 0.80 + sz * 0.05;',
    '    float gloss = gT > 0.0 ? pow(gT, 14.0) * 0.9 : 0.0;',
    '    float kT = -s.x * 0.45 - s.y * 0.88;',
    '    float stk = kT > 0.0 ? pow(kT, 34.0) * 1.4 : 0.0;',
    '    g2 = min(gloss + stk, 1.0);',
    '  }',
    // rotate the normal (BallGUI: tilt about x, then turn about y)
    '  float cX = cos(uCamX), sX = sin(uCamX), cY = cos(uCamY), sY = sin(uCamY);',
    '  float y1 = n.y * cX - n.z * sX;',
    '  float z1 = n.y * sX + n.z * cX;',
    '  float rx = n.x * cY + z1 * sY;',
    '  float ry = clamp(y1, -1.0, 1.0);',
    '  float rz = -n.x * sY + z1 * cY;',
    '  float lon = atan(rx, -rz);',
    '  float lat = asin(ry);',
    '  bool front = lon >= -HALF_PI && lon <= HALF_PI;',
    '  float lonT = front ? lon : (lon > 0.0 ? lon - PI : lon + PI);',
    '  vec2 f = vec2((lonT / PI + 0.5) * (uTex.x - 1.0), (lat / PI + 0.5) * (uTex.y - 1.0));',
    '  vec2 uv = (f + 0.5) / uTex;',
    '  vec3 c;',
    '  if (front) c = texture2D(uFront, uv).rgb * 255.0;',
    '  else c = texture2D(uBack, uv).rgb * 255.0;',
    '  if (front) {',
    '    if (uPress.z > 0.0 && f.x >= uPress.x && f.x <= uPress.x + uPress.z && f.y >= uPress.y && f.y <= uPress.y + uPress.w)',
    '      c = min(vec3(255.0), c * 1.45 + 30.0);',
    // BallGUI's luma bump
    '    float hC = lum(texture2D(uFront, uv).rgb);',
    '    float hR = lum(texture2D(uFront, uv + vec2(1.0 / uTex.x, 0.0)).rgb);',
    '    float hD = lum(texture2D(uFront, uv + vec2(0.0, 1.0 / uTex.y)).rgb);',
    '    float du = (hC - hR) * 0.22, dv = (hC - hD) * 0.22;',
    '    float uu = 0.5 + lon / TWO_PI;',
    '    vec3 bn = normalize(vec3(n.x - sin(uu * TWO_PI) * du, n.y + dv, n.z + cos(uu * TWO_PI) * du));',
    '    diff = max(0.0, -dot(bn, uL));',
    '    float st = dot(bn, uH);',
    '    spec = st > 0.0 ? pow(st, 36.0) : 0.0;',
    '  }',
    '  float amb = 0.06 + (0.75 - 0.06) * uBrt;',
    '  float dsc = 0.40 + (1.85 - 0.40) * uBrt;',
    '  float sp2 = spec * (1.1 + uBrt * 0.6);',
    '  float shade = amb + dsc * diff;',
    '  vec3 col = c * shade + sp2 * vec3(255.0, 255.0, 240.0);',
    '  col.r += (60.0 - col.r) * rim * 0.45;',
    '  col.g += (100.0 - col.g) * rim * 0.45;',
    '  col.b += (200.0 - col.b) * rim * 0.65;',
    '  if (g2 > 0.005) col += g2 * vec3(220.0, 230.0, 255.0);',
    '  return vec4(clamp(col, 0.0, 255.0) / 255.0, 1.0);',
    '}',
    'void main() {',
    '  vec2 c = vec2(gl_FragCoord.x, uSize.y - gl_FragCoord.y) - uSize * 0.5;',
    '  vec4 acc = vec4(0.0);',
    // 4 samples, rotated grid
    '  vec4 s;',
    '  s = shadeAt(c + vec2(-0.125, -0.375)); acc += vec4(s.rgb * s.a, s.a);',
    '  s = shadeAt(c + vec2( 0.375, -0.125)); acc += vec4(s.rgb * s.a, s.a);',
    '  s = shadeAt(c + vec2( 0.125,  0.375)); acc += vec4(s.rgb * s.a, s.a);',
    '  s = shadeAt(c + vec2(-0.375,  0.125)); acc += vec4(s.rgb * s.a, s.a);',
    '  gl_FragColor = acc * 0.25;',          // premultiplied, as the canvas expects
    '}'
  ].join('\n');

  var cv = null, gl = null, prog = null, U = {}, texF = null, texB = null, size = 0;
  var api = { ok: false };

  function shader(type, src) {
    var s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }

  function makeTex() {
    var t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);   // smooth near the rim
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 255]));
    return t;
  }

  try {
    cv = document.createElement('canvas');
    gl = cv.getContext('webgl', { premultipliedAlpha: true, alpha: true, antialias: false, preserveDrawingBuffer: true });
    if (gl) {
      prog = gl.createProgram();
      gl.attachShader(prog, shader(gl.VERTEX_SHADER, VS));
      gl.attachShader(prog, shader(gl.FRAGMENT_SHADER, FS));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
      gl.useProgram(prog);
      ['uFront', 'uBack', 'uSize', 'uSr', 'uFov', 'uR', 'uDist', 'uCamX', 'uCamY', 'uBrt', 'uPress', 'uL', 'uH', 'uTex']
        .forEach(function (n) { U[n] = gl.getUniformLocation(prog, n); });
      var buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
      var loc = gl.getAttribLocation(prog, 'aPos');
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      texF = makeTex();
      texB = makeTex();
      gl.uniform1i(U.uFront, 0);
      gl.uniform1i(U.uBack, 1);
      api.ok = true;
    }
  } catch (e) {
    api.ok = false;
    api.error = String(e);
  }

  function upload(t, unit, canvas) {
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, canvas);
    gl.generateMipmap(gl.TEXTURE_2D);
  }

  // front / back: the sketch's PGraphics (Processing.js keeps their canvas in .externals.canvas)
  api.textures = function (front, back) {
    if (!api.ok) return;
    if (front && front.externals) upload(texF, 0, front.externals.canvas);
    if (back && back.externals) upload(texB, 1, back.externals.canvas);
  };

  // draw the ball into the sketch's canvas at (x, y), size px square
  api.draw = function (target, x, y, sz, a) {
    if (!api.ok) return;
    if (a) {
      if (sz !== size) {
        cv.width = sz;
        cv.height = sz;
        size = sz;
        gl.viewport(0, 0, sz, sz);
      }
      gl.uniform2f(U.uSize, sz, sz);
      gl.uniform1f(U.uSr, a.sr); gl.uniform1f(U.uFov, a.fov); gl.uniform1f(U.uR, a.R); gl.uniform1f(U.uDist, a.dist);
      gl.uniform1f(U.uCamX, a.camX); gl.uniform1f(U.uCamY, a.camY); gl.uniform1f(U.uBrt, a.brt);
      gl.uniform4f(U.uPress, a.px, a.py, a.pw, a.ph);
      gl.uniform3f(U.uL, a.lx, a.ly, a.lz); gl.uniform3f(U.uH, a.hx, a.hy, a.hz);
      gl.uniform2f(U.uTex, a.tw, a.th);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    target.getContext('2d').drawImage(cv, x, y);
  };

  return api;
})();
