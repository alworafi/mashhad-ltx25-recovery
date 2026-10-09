# LTX-2.5 DIRECT FAST / RunPod

Direct API without ComfyUI. The Docker image pre-installs dependencies; on each new Pod, 5 LTX-2.5 BF16 model checkpoints are downloaded concurrently and checked. A persistent single-process API keeps one pipeline object resident between requests when GPU memory permits.

## RunPod template
- Image: ghcr.io/alworafi/ltx25-direct-fast:latest
- Workspace mount: /workspace, recommended >=150GB
- HTTP Port: 8000
- Required secrets: HF_TOKEN (if gated), DIRECT_API_TOKEN (long random value)
- DOWNLOAD_WORKERS=5; WARM_ON_BOOT=true or false
- Inputs go in /workspace/inputs/first.png and last.png
- Generation: PROMPT='cinematic transition' bash /opt/mashhad/generate.sh
- Poll /jobs/{job_id} with Authorization: Bearer DIRECT_API_TOKEN
- Output: /workspace/outputs/{job_id}.mp4

Cold start downloads models when Pod and Volume are deleted. A new GPU requires one new in-memory load. The worker executes jobs sequentially, not simultaneous GPU inference.
WARNING: BF16 direct pipeline is not mathematically equivalent to your Comfy INT8 ConvRot one-stage graph. The image and APIs have not yet been GPU tested. Before production use pin LTX_REF to a tested commit; protect exposed ports using a private network/auth.
