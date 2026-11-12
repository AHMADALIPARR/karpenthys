# JETSON.md — handoff for the Jetson side

Karpenthys is push-ready on this VM. The work that needs the Jetson is
Vulkan dispatch and WebGPU verification. This file is the checklist for
that session.

## 1. Bring the Jetson up

The Jetson (snapkitty-jetson, 100.77.155.64, user `jetson`) was down at
the last check (2026-11-11 07:35 PST): SSH fails with "Connection reset
by peer", the same signature as the 2026-11-06 memory-full event. It
cannot be rebooted remotely. Physical power-cycle, then confirm:

```
ssh jetson
```

## 2. Vulkan dispatch (the owner's verification bar)

The metal-inference tree lives at `~/workspace/metal-inference-inspect`
on this VM, branch `feat/vulkan-int4-phase-c`. It is an x86_64 build;
the Jetson needs its own build (aarch64, sm_87). Transfer the tree,
then on the Jetson:

```
cmake -S Vulkan -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/vk_dispatch list
./build/vk_dispatch embedding
./build/vk_dispatch matvec
```

Expected receipts for the bar: (1) actual dispatch without
BLOCKED_NO_PHYSICAL_DEVICE, (2) GPU readback values, (3) numerical
comparison against the CPU oracle (the oracle is in
`Vulkan/int4_oracle.cpp`, 31/31 on this VM), (4) at least one completed
autoregressive decoding sequence. Record the receipts; do not claim
any of the four until the numbers exist.

After a successful dispatch, re-export the manifest on the Jetson
(`./build/vk_dispatch manifest 1` / `2`) and copy the new manifests
back into this repo's `manifests/`. Note: the manifest writer currently
records the execution block as NOT_EXECUTED; wiring a real dispatch
receipt into the execution block is an open step, not yet implemented.
Until that lands, the manifest stays NOT_EXECUTED and the interface
keeps saying so.

## 3. WebGPU verification

On the Jetson, open `webgpu.html` in Chrome. If the browser reports no
adapter, try Chrome with WebGPU enabled (`--enable-unsafe-webgpu`) or
a Chromium build with ANGLE/Vulkan. Confirm:

- the status pill reads WEBGPU with adapter info (not "unavailable"),
- the core, tubes, and nodes render,
- clicking a node opens the inspector with real values,
- the 1-layer / 2-layer toggle works,
- no page errors.

Screenshot both layer counts and save them as the verification
evidence. If the Jetson's Chrome has no working WebGPU either, record
that as a measured fact and stop; do not claim the renderer verified.

## 4. Push

The repo is ready to push when the owner names the destination repo
and drops a fresh single-use token. Push account is AHMADALIPARR.
LICENSE is the canonical Sovereign license (verified against the
canonical copy). WATERMARK.md is the hash-chained manifest of the tree.
