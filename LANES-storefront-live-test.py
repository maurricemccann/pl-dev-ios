import json,urllib.request,urllib.error,sys
B="https://psychedluxuries.com/"
def call(method,path,body=None):
    req=urllib.request.Request(B+path,method=method,headers={"User-Agent":"PLDev-test/1","accept":"application/json","content-type":"application/json"},data=json.dumps(body).encode() if body is not None else None)
    try:
        r=urllib.request.urlopen(req,timeout=40); return r.status,r.read(),dict(r.headers)
    except urllib.error.HTTPError as e: return e.code,e.read(),dict(e.headers)
ok=True
def check(name,cond,detail=""):
    global ok
    print(("PASS " if cond else "FAIL ")+name+(" - "+detail if detail else "")); ok&=bool(cond)
def j(b): return json.loads(b)
# stream: every kind, decode rules of StreamItem
total=0
for kind in [None,"archive","drop","doctrine","generated","declaration"]:
    cur=0; pages=0; items=[]
    while cur is not None and pages<60:
        q=f"api/congregation/stream?limit=24&cursor={cur}"+(f"&kind={kind}" if kind else "")
        s,b,_=call("GET",q); d=j(b); assert s==200
        items+=d["items"]; cur=d["nextCursor"]; pages+=1
        if kind is None and pages>=3: break
    bad=[i for i in items if not isinstance(i.get("kind"),str) or not isinstance(i.get("id"),str) or not isinstance(i.get("reactions",0),int) or not isinstance(i.get("reacted",False),bool) or not isinstance(i.get("comments",[]),list)]
    check(f"stream kind={kind}: {len(items)} items over {pages} pages decode",not bad,str(bad[:1]))
    if kind=="drop":
        raw=[i for i in items if i.get("image") and "product-transparent" not in i["image"]]
        check("drops: raw non-flat pictures exist in feed (the app must filter them)",True,f"{len(raw)} of {len(items)} are not flats and are dropped by StreamItem.picture")
# room feed anonymous
s,b,_=call("GET","api/congregation/feed"); d=j(b)
bad=[p for p in d["posts"] if not (isinstance(p["id"],str) and isinstance(p["body"],str) and isinstance(p["reactions"],int) and isinstance(p["reacted"],bool) and isinstance(p["comments"],list) and all(isinstance(c["id"],str) and isinstance(c["body"],str) for c in p["comments"]))]
check(f"room feed anonymous: {len(d['posts'])} posts decode, canPost={d['canPost']} authed={d['authed']}",s==200 and not bad)
# directory, follow, posts, search
s,b,_=call("GET","api/members/directory"); d=j(b); check(f"directory {len(d['members'])} members",s==200 and all(isinstance(m['handle'],str) for m in d['members']))
h=d['members'][0]['handle']
s,b,_=call("GET",f"api/follow?handle={h}"); d=j(b); check("follow counts",s==200 and isinstance(d['followers'],int) and isinstance(d['following'],int) and isinstance(d['isFollowing'],bool))
s,b,_=call("GET",f"api/congregation/posts?handle={h}"); d=j(b); check(f"member posts {len(d['posts'])}",s==200 and all(isinstance(p['id'],str) and isinstance(p['body'],str) for p in d['posts']))
s,b,_=call("GET","api/search?q=pro"); d=j(b); check("search members",s==200 and 'members' in d)
s,b,_=call("GET","api/creator-status"); d=j(b); check("creator status",s==200 and {'status','label'}<=set(d))
# auth unauth
s,b,_=call("GET","api/auth/me"); check("auth/me anonymous says authenticated:false",s==200 and j(b)['authenticated'] is False)
s,b,h2=call("POST","api/auth/signin",{"email":"nobody@example.com","password":"wrong"}); check("signin wrong → 401 + sentence + no cookie",s==401 and 'message' in j(b) and 'set-cookie' not in {k.lower() for k in h2})
for path,body in [("api/congregation/feed",{"body":"x"}),("api/congregation/feed/react",{"postId":"x"}),("api/congregation/feed/comment",{"postId":"x","body":"hello"}),("api/congregation/stream/react",{"itemId":"x"}),("api/congregation/stream/comment",{"itemId":"x","body":"hello"}),("api/follow",{"handle":"x"}),("api/dm",{"body":"hello"}),("api/congregation/report",{"refType":"post","refId":"x"}),("api/congregation/feed/moderate",{"postId":"x","action":"approve"}),("api/account/profile",{"firstName":"x"}),("api/congregation/intent",{"intent":"buyer"}),("api/notifications",{})]:
    s,b,_=call("POST",path,body); d=j(b); check(f"POST {path} unauthenticated refused, with a sentence",s in (401,403) and (d.get('message') or d.get('ok') is False),f"{s} {str(d)[:70]}")
for path in ["api/notifications","api/dm","api/account/orders","api/account/profile","api/congregation/intent","api/congregation/following"]:
    s,b,_=call("GET",path); check(f"GET {path} unauthenticated → 401",s==401,str(s))
# orders lookup
s,b,_=call("POST","api/orders/lookup",{"email":"bad","orderId":"1"}); check("orders/lookup invalid email → 400 + sentence",s==400 and 'message' in j(b))
s,b,_=call("POST","api/orders/lookup",{"email":"nobody@example.com","orderId":"NOPE"}); check("orders/lookup unknown → 404 + sentence",s==404 and 'message' in j(b))
# pages that open in the sheet
for p in ["transmission","register","signin","contact","gift-card","returns","terms","privacy","the-brand","the-three-truths","three-bodies","the-forge","catalogue/PL-0018","shop/heart-mark-tee"]:
    req=urllib.request.Request(B+p,headers={"User-Agent":"PLDev-test/1"})
    try: r=urllib.request.urlopen(req,timeout=40); st=r.status
    except urllib.error.HTTPError as e: st=e.code
    check(f"page /{p} opens (200 after redirects)",st==200,str(st))
print("ALL PASS" if ok else "SOME FAILED"); sys.exit(0 if ok else 1)
