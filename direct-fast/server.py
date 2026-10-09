import os,time,uuid,threading,queue,traceback
from pathlib import Path
from fastapi import FastAPI,HTTPException,Header
from pydantic import BaseModel,Field
from engine import Engine
app=FastAPI(title="Mashhad LTX-2.5 Direct FAST")
engine=Engine();jobs={};job_queue=queue.Queue();lock=threading.Lock()
INPUT=Path("/workspace/inputs");OUTPUT=Path("/workspace/outputs")
INPUT.mkdir(parents=True,exist_ok=True);OUTPUT.mkdir(parents=True,exist_ok=True)
class Request(BaseModel):
    first:str="first.png";last:str="last.png";prompt:str=Field(min_length=1)
    seed:int=873293130933086;width:int=1280;height:int=720;frames:int=121;fps:int=24
    strength:float=Field(default=0.7,ge=0,le=1)
def auth(header):
    token=os.getenv("DIRECT_API_TOKEN","")
    if not token or header!="Bearer "+token:raise HTTPException(401,"Unauthorized")
def input_path(name):
    if Path(name).name!=name or name.startswith("."):raise ValueError("invalid filename")
    p=INPUT/name
    if p.is_symlink() or not p.is_file() or not p.stat().st_size:raise ValueError("missing image: "+name)
    return str(p)
def worker():
    while True:
        jid,req=job_queue.get()
        with lock:jobs[jid].update(state="running",started=time.time())
        try:
            out=str(OUTPUT/(jid+".mp4"))
            result=engine.generate(input_path(req.first),input_path(req.last),req.prompt,req.seed,req.width,req.height,req.frames,req.fps,out,req.strength)
            with lock:jobs[jid].update(state="finished",result=result,finished=time.time())
        except Exception as e:
            traceback.print_exc()
            with lock:jobs[jid].update(state="failed",error=str(e),finished=time.time())
        finally:job_queue.task_done()
@app.on_event("startup")
def startup():
    threading.Thread(target=worker,daemon=True).start()
    if os.getenv("WARM_ON_BOOT","false").lower()=="true":
        def warm():
            try:engine.load();print("MODEL_LOADED_SECONDS",engine.load_seconds,flush=True)
            except Exception:traceback.print_exc()
        threading.Thread(target=warm,daemon=True).start()
@app.get("/health")
def health():return {"status":"online","model_loaded":engine.pipeline is not None,"load_seconds":engine.load_seconds,"queue_size":job_queue.qsize()}
@app.post("/generate")
def create(req:Request,authorization:str|None=Header(default=None)):
    auth(authorization)
    if req.frames<9 or req.frames%8!=1 or req.width%32 or req.height%32:raise HTTPException(422,"frames must be 8n+1; dimensions multiples of 32")
    try:input_path(req.first);input_path(req.last)
    except ValueError as e:raise HTTPException(422,str(e)) from e
    jid=uuid.uuid4().hex
    with lock:jobs[jid]={"state":"queued","created":time.time()}
    job_queue.put((jid,req));return {"job_id":jid,"state":"queued"}
@app.get("/jobs/{jid}")
def status(jid:str,authorization:str|None=Header(default=None)):
    auth(authorization)
    with lock:record=jobs.get(jid)
    if record is None:raise HTTPException(404,"unknown job")
    return record
