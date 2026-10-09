# Mashhad LTX-2.5 ComfyUI Docker

صورة ComfyUI مستقلة ومتوافقة مع Mashhad Worker. تحتوي على PyTorch/CUDA وComfyUI
وعقد LTX الرسمية داخل الصورة، بينما تحفظ موديلات ComfyUI السبعة فقط على Network
Volume في `/workspace/LTX25/models/ltx-2.5`.

المتطلبات عند التشغيل:

- Network Volume مربوط على `/workspace`.
- `HF_TOKEN` صالح للوصول إلى `Lightricks/LTX-2.5`.
- `MASHHAD_PREPARE_ENGINES=comfyui`.
- يفضّل تشغيلها من قالب Mashhad ComfyUI داخل الموقع كي يرفع الموقع نسخته الحالية
  من Worker تلقائيًا بعد ظهور علامة الجاهزية.
