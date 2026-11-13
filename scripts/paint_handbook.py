"""Builds PLDev/Sections/Paint/Native/NativeHandbook.json from the laptop's handbook (C:/dev/pl-paint/src/handbook/index.html).
Chapters (h2) hold sections (h3); a section holds blocks: lead, p, tip, h4, list, steps, figure (picture + numbered legend), table.
Pictures stay on the gallery (/paint/handbook/img/...) and load at run time. Run again when the laptop handbook changes."""
import json, re, sys
from bs4 import BeautifulSoup

SRC = 'C:/dev/pl-paint/src/handbook/index.html'
OUT = sys.argv[1] if len(sys.argv) > 1 else 'PLDev/Sections/Paint/Native/NativeHandbook.json'
soup = BeautifulSoup(open(SRC, encoding='utf-8').read(), 'html.parser')
main = soup.find('main')

def text(el):
    return re.sub(r'\s+', ' ', el.get_text(' ', strip=True)).replace(' ,', ',').replace(' .', '.').replace(' ;', ';').replace(' :', ':').strip()

def block(el):
    cls = el.get('class') or []
    n = el.name
    if n == 'p': return {'t': 'lead' if 'lead' in cls else 'p', 'x': text(el)}
    if n == 'aside': 
        b = el.find('b'); head = text(b) if b else ''
        t = text(el); body = t[len(head):].strip() if head and t.startswith(head) else t
        return {'t': 'tip', 'h': head, 'x': body}
    if n == 'h4': return {'t': 'h4', 'x': text(el)}
    if n in ('ul', 'ol'): return {'t': 'steps' if (n == 'ol' or 'steps' in cls) else 'list', 'x': [text(li) for li in el.find_all('li', recursive=False)]}
    if n == 'table':
        rows = [[text(c) for c in tr.find_all(['th', 'td'])] for tr in el.find_all('tr')]
        return {'t': 'table', 'x': rows}
    if n == 'figure':
        img = el.find('img'); leg = el.find('ol', class_='legend')
        items = []
        if leg:
            for li in leg.find_all('li', recursive=False):
                b = li.find('b'); cd = li.find('span', class_='cd')
                items.append([text(b) if b else '', text(cd) if cd else ''])
        return {'t': 'fig', 'src': img['src'] if img else '', 'alt': img.get('alt', '') if img else '', 'x': items}
    if n == 'div' and 'idx' in cls: return None
    return None

chapters = []
cur = None
for el in main.find_all(['h2', 'section'], recursive=False):
    if el.name == 'h2':
        num = el.find('span'); num_t = text(num) if num else ''
        title = text(el)
        if num_t and title.startswith(num_t): title = title[len(num_t):].strip()
        cur = {'id': el.get('id', ''), 'n': num_t, 'title': title, 'secs': []}
        chapters.append(cur)
    elif cur is not None:
        h3 = el.find('h3')
        blocks = [b for b in (block(c) for c in el.children if getattr(c, 'name', None)) if b]
        blocks = [b for b in blocks if b.get('t') != 'h3']
        cur['secs'].append({'id': el.get('id', ''), 'title': text(h3) if h3 else el.get('data-t', ''), 'b': blocks})
json.dump({'chapters': chapters}, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(len(chapters), 'chapters', sum(len(c['secs']) for c in chapters), 'sections', sum(len(s['b']) for c in chapters for s in c['secs']), 'blocks')
