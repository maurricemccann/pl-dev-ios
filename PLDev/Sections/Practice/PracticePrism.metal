#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The Prism: the fragment shader of `public/app.js` initPrism (the gallery's 'prism' piece), line for line. The web's time uniform
// advances at 1/6 speed and the caustic field swells with the breath envelope; the app passes both in.

static float pr_hash(float2 p) { return fract(sin(dot(p, float2(41.3, 289.1))) * 43758.5453); }

static float pr_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = pr_hash(i), b = pr_hash(i + float2(1.0, 0.0)), c = pr_hash(i + float2(0.0, 1.0)), d = pr_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float pr_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * pr_noise(p); p = p * 2.03 + float2(1.7); a *= 0.5; }
    return v;
}

static float pr_caustic(float2 uv, float t) {
    float2 w = float2(pr_fbm(uv * 2.2 + t * 0.3), pr_fbm(uv * 2.2 - t * 0.25 + 4.1));
    return pr_fbm(uv * 2.2 + w * 2.2 + t * 0.15);
}

[[ stitchable ]] half4 practicePrism(float2 position, half4 color, float2 size, float time, float breath) {
    float2 uv = float2(position.x / size.x, 1.0 - position.y / size.y);
    uv.x *= size.x / size.y;
    float t = time * 0.2;
    float base = pr_caustic(uv, t);
    float g = smoothstep(0.32, 0.68, base);
    float3 bg = float3(0.043, 0.039, 0.027), gold = float3(0.788, 0.659, 0.298), ink = float3(0.102, 0.082, 0.063);
    float3 col = mix(bg, gold * (0.9 + 0.35 * breath), g);
    col = mix(col, ink, smoothstep(0.0, 0.18, base) * 0.55);
    float off = 0.006;
    float edge = pr_caustic(uv + float2(off, 0.0), t) - pr_caustic(uv - float2(off, 0.0), t);
    col += float3(1.0, 0.0, -1.0) * edge * 1.4 * (0.6 + 0.6 * breath);
    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}
