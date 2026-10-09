#!/usr/bin/env bash
set -Eeuo pipefail
: "${DIRECT_API_TOKEN:?Set DIRECT_API_TOKEN}"
: "${PROMPT:?Set PROMPT}"
python - <<'PY'
import json,os,urllib.request
body={"first":os.getenv("FIRST_FRAME","first.png"),"last":os.getenv("LAST_FRAME","last.png"),"prompt":os.environ["PROMPT"],"seed":int(os.getenv("SEED","873293130933086")),"width":int(os.getenv("WIDTH","1280")),"height":int(os.getenv("HEIGHT","720")),"frames":int(os.getenv("FRAMES","121")),"fps":int(os.getenv("FPS","24")),"strength":float(os.getenv("STRENGTH","0.7"))}
req=urllib.request.Request("http://127.0.0.1:8000/generate",data=json.dumps(body).encode(),headers={"Content-Type":"application/json","Authorization":"Bearer "+os.environ["DIRECT_API_TOKEN"]},method="POST")
print(urllib.request.urlopen(req).read().decode())
PY
