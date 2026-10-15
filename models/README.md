# Models

`u2netp.onnx`: U²-Net's small model (u2netp), which finds the subject of a
song's cover for the 3D cover in Now Playing, on Windows and Linux (the app,
with ONNX Runtime) and in the Omarchy shell plugin (`paattu/depth.py`).
Android uses ML Kit's subject segmentation instead.

- From: https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx
  (the ONNX export of the weights from https://github.com/xuebinqin/U-2-Net)
- SHA-256: `309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8`
- Licence: Apache License 2.0 (U²-Net, Xuebin Qin et al., "U²-Net: Going
  Deeper with Nested U-Structure for Salient Object Detection", Pattern
  Recognition 2020)
- Input: 1×3×320×320 RGB, scaled by its brightest value, then normalised
  with ImageNet's means (0.485, 0.456, 0.406) and spreads (0.229, 0.224,
  0.225). Output: the first output, 1×1×320×320, how sure each pixel is
  the subject.
