# STATUS — Karpenthys

Plain facts about what is verified and what is not. No claims beyond
what was measured on the machine that did the measuring.

## Verified on this VM (2026-11-11)

- OCaml synthesis engine (`ocaml/karp`, OCaml 5.5.2, stdlib only):
  both manifests validate (15/15 and 26/26 nodes, all validated);
  schemas are byte-identical across repeated runs; the independent
  Python cross-check passes on every node position, edge control point,
  color, radius, and total for both layer counts; a tampered manifest
  (node_count 99 vs 15 nodes) is rejected with exit 2 and both failure
  lines printed. `sh tests/run.sh` → KARP TESTS OK.
- WebGL engine (`index.html`, Three.js r149 + UnrealBloomPass):
  checked headless (Chromium + SwiftShader WebGL): composer and bloom
  live, 15/26 nodes render, inspector shows real fused_qkv values
  (C(signed,group64,flat), fused_qkv.spv), 15/26 telemetry bars render,
  scene positions match the OCaml schema exactly (max error 0),
  zero page errors. Screenshots: `shot-desktop.png`,
  `shot-2layers.png`.
- `build.sh` reproduces byte-identical `index.html` and `webgpu.html`.
- WebGPU page (`webgpu.html`): JavaScript syntax-checks clean
  (`node --check`); headless load shows the honest fallback (no
  adapter on this machine), inspector and telemetry dock populate,
  layer toggle works, zero page errors.
  Screenshot: `shot-webgpu-fallback.png`.

## Not verified — explicitly outstanding

- WebGPU rendering: no WebGPU adapter exists on this VM in any tested
  flag combination (`navigator.gpu` present on the page, `requestAdapter`
  returns null). The WGSL shaders, pipelines, and scene have never
  executed. Verification is a Jetson step (see JETSON.md).
- Vulkan dispatch, GPU readback, oracle comparison, autoregressive
  decoding: all outstanding, per the owner's verification bar. The
  manifest execution block says NOT_EXECUTED and the interface repeats
  it. The Jetson is down (SSH reset by peer, last checked 2026-11-11
  07:35 PST) and needs a physical power-cycle.
- Flow particles carry no telemetry and the particle shell, starfield,
  and circuit floor are environment, not data. The interface states
  this.

## Known cosmetic limits

- Some label crowding in the 2-layer top cluster.
- The argmax label can overlap the legend at some orbit angles.
