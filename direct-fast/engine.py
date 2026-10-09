import os,time,threading
from pathlib import Path
M=Path(os.getenv("MODEL_DIR","/workspace/models/ltx-2.5"))
class Engine:
    def __init__(self):
        self.pipeline=None;self.load_seconds=None;self._load_lock=threading.Lock()
    def load(self):
        with self._load_lock:
            if self.pipeline is not None:return
            from ltx_pipelines.distilled import DistilledPipeline
            from ltx_pipelines.utils.model_paths import ModelPaths
            t=time.monotonic()
            paths=ModelPaths.from_split(
                transformer_path=str(M/"diffusion_models/ltx-2.5-22b-distilled-transformer-bf16.safetensors"),
                text_encoder_path=str(M/"text_encoders/gemma4-12b-with-proj-ltx-2.5-bf16.safetensors"),
                video_vae_path=str(M/"vae/ltx-2.5-video-vae-bf16.safetensors"),
                audio_vae_path=str(M/"vae/ltx-2.5-audio-vae-bf16.safetensors"))
            self.pipeline=DistilledPipeline(model_paths=paths,spatial_upsampler_path=str(M/"latent_upscale_models/ltx-2.5-latent-spatial-upscaler-x2-bf16-1.0.safetensors"),loras=[])
            self.load_seconds=round(time.monotonic()-t,2)
    def generate(self,first,last,prompt,seed,width,height,frames,fps,out,strength):
        from ltx_pipelines.utils.types import ImageConditioningInput
        from ltx_pipelines.utils.media_io import encode_video
        self.load();begin=time.monotonic()
        result=self.pipeline(prompt=prompt,seed=seed,width=width,height=height,num_frames=frames,frame_rate=fps,images=[ImageConditioningInput(first,0,strength),ImageConditioningInput(last,frames-1,strength)])
        encode_video(video=result.video,fps=fps,audio=result.audio,output_path=out)
        return {"generation_seconds":round(time.monotonic()-begin,2),"model_load_seconds":self.load_seconds,"output":out}
