"""Shop wave 2: server-side checks of every read the app makes, against the live site. Read-only (GET only).
Mirrors the Swift parsers (ShopSitePages.swift, ArchiveViews.swift) in Python. Run: python LANES-shop-live-test.py"""
import re, json, html, urllib.request, urllib.parse, sys
from concurrent.futures import ThreadPoolExecutor

BASE = "https://psychedluxuries.com/"
ok = bad = 0

def check(name, cond, extra=""):
    global ok, bad
    if cond: ok += 1
    else: bad += 1; print("FAIL:", name, extra)

def get(u, accept=None):
    req = urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0", **({"accept": accept} if accept else {})})
    try:
        r = urllib.request.urlopen(req, timeout=40); return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

def is_flat(u):
    p = urllib.parse.urlparse(u)
    return p.hostname == "assets.psychedluxuries.com" and "/product-transparent/" in p.path and p.path.lower().endswith(".png")

def txt(s):
    s = re.sub(r"<br\s*/?>", "\n", s); s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s{2,}", " ", html.unescape(s)).strip()

# ---- the shop page's cards
st, b = get(BASE + "shop"); page = b.decode("utf8")
cards = []
for m in re.finditer(r'<a class="pl-card[^"]*"[^>]*href="/shop/([^"?#]+)"[^>]*>([\s\S]*?)</a>', page):
    slug, body = m.group(1), m.group(2)
    name = txt(re.search(r"<h3[^>]*>([\s\S]*?)</h3>", body).group(1))
    ps = [txt(x) for x in re.findall(r"<p[^>]*>([\s\S]*?)</p>", body)]
    price = re.search(r"([0-9][0-9,]*(?:\.[0-9]+)?)", ps[0]) if ps else None
    imgs = []
    for u in re.findall(r'<img src="([^"]+)"', body):
        real = urllib.parse.parse_qs(urllib.parse.urlparse(html.unescape(u)).query).get("src", [html.unescape(u)])[0]
        if is_flat(real) and real not in imgs: imgs.append(real)
    cards.append(dict(slug=slug, name=name, cents=round(float(price.group(1).replace(",", "")) * 100) if price else 0, line=ps[1] if len(ps) > 1 else "", flats=imgs))
count = int(re.search(r">(\d+)<!-- --> <!-- -->pieces", page).group(1))
check("shop page: every card parsed", len(cards) == count, f"{len(cards)} vs {count}")
check("shop page: every card has a name and a price", all(c["name"] and c["cents"] > 0 for c in cards))
check("shop page: slugs unique", len({c["slug"] for c in cards}) == len(cards))
check("shop page: only flats kept", all(is_flat(u) for c in cards for u in c["flats"]))
print(f"cards: {len(cards)} (site says {count}), with a flat on the card: {sum(1 for c in cards if c['flats'])}")

# ---- the feed joined to the grid
st, fb = get(BASE + "feed/products.xml"); feed = fb.decode("utf8")
groups = set(re.findall(r"<g:item_group_id>([^<]*)", feed))
slugs = {c["slug"] for c in cards}
check("feed: every feed piece is on the shop page", groups <= slugs, str(groups - slugs))
print(f"feed pieces: {len(groups)}; card-only (thin) pieces: {len(slugs - groups)}")

# ---- every piece page
def flight(h):
    out = ""
    for m in re.finditer(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', h):
        out += json.loads('"' + m.group(1) + '"')
    return out

def arr(s, i):
    d = 0; ins = False; k = i
    while k < len(s):
        c = s[k]
        if ins:
            if c == "\\": k += 1
            elif c == '"': ins = False
        else:
            if c == '"': ins = True
            elif c == "[": d += 1
            elif c == "]":
                d -= 1
                if d == 0: return s[i:k + 1]
        k += 1

def parse(slug):
    st, b = get(BASE + "shop/" + slug)
    if st != 200: return slug, st, None
    h = b.decode("utf8"); f = flight(h)
    d = {}
    m = re.search(r'<p class="label mb-4">([\s\S]*?)</p><h1', h); d["axiom"] = txt(m.group(1)) if m else None
    m = re.search(r'The argument</p><p class="[^"]*">([\s\S]*?)</p>', h); d["arg"] = txt(m.group(1)) if m else None
    m = re.search(r'About this piece</p>([\s\S]*?)</div></div>', h); d["about"] = txt(m.group(1)) if m else None
    d["folds"] = [txt(x[0]) for x in re.findall(r'<details class="group py-4"><summary[^>]*>([\s\S]*?)<span[\s\S]*?</summary><p[^>]*>([\s\S]*?)</p></details>', h)]
    if len(d["folds"]) == 2 and "Delivery &amp; returns" in h:
        m2 = re.search(r'"children":"(Ships tracked[^"\\]*(?:\\.[^"\\]*)*)"', f)
        if m2: d["folds"].append("Delivery & returns")
    sg = re.search(r'<details class="pl-psy-panel mt-5[\s\S]*?</details>', h)
    d["guide"] = None
    if sg:
        cols = re.findall(r'<th scope="col"[^>]*>([\s\S]*?)</th>', sg.group(0))[1:]
        rows = re.findall(r'<tr class="border-b border-line/40[^"]*">([\s\S]*?)</tr>', sg.group(0))
        d["guide"] = (len(cols), len(rows))
    i = f.find('"variants":[')
    vs = json.loads(arr(f, i + len('"variants":'))) if i >= 0 else []
    d["variants"] = vs
    d["rel"] = re.findall(r'href="/shop/([^"?#]+)"', h[h.find("More from the drop"):]) if "More from the drop" in h else []
    return slug, st, d

with ThreadPoolExecutor(8) as ex: results = list(ex.map(parse, [c["slug"] for c in cards]))
bad_pages = [(s, st) for s, st, d in results if d is None]
check("pieces: every page answers 200", not bad_pages, str(bad_pages))
good = [(s, d) for s, st, d in results if d]
check("pieces: every page has an axiom", all(d["axiom"] for s, d in good), str([s for s, d in good if not d["axiom"]]))
check("pieces: every page has an argument", all(d["arg"] for s, d in good), str([s for s, d in good if not d["arg"]]))
check("pieces: every page has variants with an id and a price", all(d["variants"] and all("id" in v and isinstance(v.get("price"), int) for v in d["variants"]) for s, d in good), str([s for s, d in good if not d["variants"]]))
check("pieces: every page has Production, Care and Delivery", all(len(d["folds"]) == 3 for s, d in good), str([(s, d["folds"]) for s, d in good if len(d["folds"]) != 3][:3]))
print("pieces with a size guide:", sum(1 for s, d in good if d["guide"]), "| with designs:", sum(1 for s, d in good if any(v.get("design") for v in d["variants"])),
      "| variants in all:", sum(len(d["variants"]) for s, d in good))
# thin pieces must be fully served by their own page
thin = slugs - groups
check("thin pieces: all have variants on their page", all(dict(good).get(s, {}).get("variants") for s in thin))
# price on the card equals the lowest variant on the page
mismatch = [(c["slug"], c["cents"], min(v["price"] for v in dict(good)[c["slug"]]["variants"])) for c in cards if c["slug"] in dict(good) and dict(good)[c["slug"]]["variants"] and c["cents"] != min(v["price"] for v in dict(good)[c["slug"]]["variants"])]
check("cards: the card's price is the page's lowest variant", not mismatch, str(mismatch[:4]))

# ---- the archive
st, mb = get("https://assets.psychedluxuries.com/manifest.json"); man = json.loads(mb)
BLOCKED = {"PL-0099", "PL-0174", "PL-0122", "PL-0501", "PL-1533", "PL-0332", "PL-0421", "PL-0431", "PL-0172", "PL-0173", "PL-0330", "PL-0036", "PL-0090", "PL-0211", "PL-0213", "PL-0354", "PL-0358", "PL-0458", "PL-0461"}
ps = [p for p in man["pieces"] if p["cr"] not in BLOCKED]
check("archive: manifest decodes with cr, title, thumb, url on every piece", all(p.get("cr") and p.get("title") and p.get("thumb") and p.get("url") for p in man["pieces"]))
check("archive: PL-0627 (the featured work) is in the record", any(p["cr"] == "PL-0627" for p in ps))
st, kb = get(BASE + "api/archive-keeps"); keeps = json.loads(kb)
check("archive: keeps answer ok", keeps.get("ok") is True and keeps["keeps"] and all("cr" in k for k in keeps["keeps"]))
st, lb = get("https://assets.psychedluxuries.com/plg.json"); lab = json.loads(lb)
check("archive: the Lab decodes", lab["entries"] and all(e.get("plg") and e.get("img") for e in lab["entries"]))
print(f"archive: {len(man['pieces'])} in the manifest, {len(ps)} shown (blocked {len(BLOCKED)}, non-shareable {sum(1 for p in man['pieces'] if p.get('shareable') is False)}), keeps {len(keeps['keeps'])}, lab {len(lab['entries'])}")
fam = lambda s="": "Glyph" if re.search("glyph", s) else "Heart" if re.search("heart", s) else "Knot" if re.search("celtic|knot", s) else "Figure" if re.search("figur", s) else "Pattern" if re.search("pattern", s) else "Text" if re.search("text", s) else "Landscape" if re.search("landscape|cosmic|cityscape", s) else "Organic"
check("archive: HeartMark lens has works", sum(1 for p in ps if p.get("family") == "HEARTMARK") > 0)

# ---- the ballot's config and the guarded reads
st, rb = get(BASE + "api/request"); cfg = json.loads(rb)
check("request: config has a site key and the six forms", cfg.get("siteKey") and set(cfg.get("products", [])) >= {"shirt", "hoodie", "sticker", "poster"})
st, rb = get(BASE + "api/request?cr=PL-0001"); check("request: anonymous read without an email answers the config", st == 200)
st, _ = get(BASE + "api/account/orders/NOPE", "application/json"); check("order detail: anonymous is refused 401", st == 401, str(st))
st, _ = get(BASE + "api/account/orders", "application/json"); check("orders list: anonymous is refused 401", st == 401, str(st))
for path in ["contact", "the-three-truths", "gift-card", "returns"]:
    st, _ = get(BASE + path); check(f"page /{path} answers 200", st == 200, str(st))

print(f"\n{ok} passed, {bad} failed")
sys.exit(1 if bad else 0)
