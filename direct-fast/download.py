import concurrent.futures,json,os,time
from pathlib import Path
from huggingface_hub import HfApi,hf_hub_download
from safetensors import safe_open
from models import MODEL_REPO,FILES
BASE=Path(os.getenv("MODEL_DIR","/workspace/models/ltx-2.5"))
TOKEN=os.getenv("HF_TOKEN") or None
WORKERS=max(1,min(5,int(os.getenv("DOWNLOAD_WORKERS","5"))))
def check(path,expected):
    if not path.is_file() or path.stat().st_size!=expected:return False
    try:
        with safe_open(str(path),framework="pt",device="cpu") as f:return len(f.keys())>0
    except Exception:return False
def main():
    started=time.monotonic();BASE.mkdir(parents=True,exist_ok=True)
    info=HfApi(token=TOKEN).model_info(MODEL_REPO,files_metadata=True)
    metadata={x.rfilename:x.size for x in info.siblings}
    missing=[x for x in FILES if not isinstance(metadata.get(x),int) or metadata[x]<=0]
    if missing:raise RuntimeError(f"Missing upstream files: {missing}")
    def worker(rel):
        dest=BASE/rel;size=metadata[rel];t=time.monotonic()
        if check(dest,size):return {"file":rel,"status":"cached","seconds":0}
        for attempt in range(1,4):
            try:
                p=hf_hub_download(repo_id=MODEL_REPO,filename=rel,local_dir=str(BASE),token=TOKEN,force_download=attempt>1)
                if not check(Path(p),size):raise RuntimeError("bad size/header")
                duration=round(time.monotonic()-t,2);print("FILE_OK",rel,duration,flush=True)
                return {"file":rel,"status":"downloaded","seconds":duration}
            except Exception as e:
                print("RETRY",attempt,rel,str(e),flush=True)
                if attempt==3:raise
                time.sleep(3*attempt)
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        results=list(pool.map(worker,FILES))
    total=round(time.monotonic()-started,2)
    (BASE/"download_report.json").write_text(json.dumps({"total_seconds":total,"files":results},indent=2))
    print("ALL_MODELS_VERIFIED",total,flush=True)
if __name__=="__main__":main()
