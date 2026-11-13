# Mirrors GLSLtoMSL.translate (PieceShader.swift) so the translated Metal source can be read before a device runs it.
import re, sys, json, subprocess
def translate(frag):
    s = re.sub(r'/\*[\s\S]*?\*/', ' ', frag)
    s = re.sub(r'//[^\n]*', ' ', s)
    s = re.sub(r'precision\s+\w+\s+\w+\s*;', '', s)
    s = re.sub(r'uniform\s+[^;]*;', '', s)
    for a, b in [('vec2','float2'),('vec3','float3'),('vec4','float4'),('mat2','float2x2'),('mat3','float3x3'),('mat4','float4x4'),('ivec2','int2'),('bvec2','bool2')]:
        s = re.sub(r'\b%s\b' % a, b, s)
    m = re.search(r'void\s+main\s*\(\s*(void)?\s*\)\s*\{', s)
    if not m: return None
    helpers = s[:m.start()]
    depth = 1; i = m.end(); end = None
    while i < len(s):
        if s[i] == '{': depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0: end = i; break
        i += 1
    if end is None: return None
    return helpers, s[m.end():end]
js = open('C:/dev/pl-curves-gallery/public/scripts/pieces.js', encoding='utf8').read()
for m in re.finditer(r"shaderPiece\(\{\s*id:'(\w+)'.*?frag:`(.*?)`", js, re.S):
    r = translate(m.group(2))
    print('==', m.group(1), 'OK' if r else 'FAIL')
    if r and m.group(1) in (sys.argv[1:] or ['tunnel']):
        print('HELPERS:', r[0].strip()[:600]); print('BODY:', r[1].strip()[:900])
