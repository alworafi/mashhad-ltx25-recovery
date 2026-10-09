# Mashhad LTX-2.5 Direct Docker

صورة Direct Python مستقلة ومتوافقة مع Mashhad Worker. تحتوي داخل الصورة على
PyTorch/CUDA وLTX-2، وتضع الموديلات فقط على Network Volume في المسار
`/workspace/LTX25/models/ltx-2.5`.

المتطلبات عند التشغيل:

- Network Volume مربوط على `/workspace`.
- `HF_TOKEN` صالح للوصول إلى `Lightricks/LTX-2.5`.
- `MASHHAD_PREPARE_ENGINES=direct`.
- يفضّل تشغيلها من قالب Mashhad Direct داخل الموقع كي يرفع الموقع نسخته الحالية
  من Worker تلقائيًا بعد ظهور علامة الجاهزية.

هذه الصورة لا تشغّل API خاصًا منافسًا على المنفذ 8000؛ المنفذ محجوز لـ Mashhad Worker.
