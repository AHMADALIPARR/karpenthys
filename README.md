# Karpenthys

Karpenthys is a read-only 3D engine for the Phase C command graph of the
Metal-to-Vulkan INT4 transformer. It renders the validated graph as a
GPU spatial environment: a massive luminous core at the center, the
transformer layers orbiting it as rings of modules, curved execution
flow between them, and a telemetry dock fed by the same manifest that
drives the geometry. The graph data is real. The execution state is
honest: nothing here has run on a GPU yet, and the interface says so.

The name comes from a mangled screenshot footer. "KARPATHY / REPO SWARM"
became "Karpenthys" in another agent's proposal, and the owner kept the
name for his own frontend. The frontend is his; the mangling is not
anyone's system.

## The data contract

Everything visible comes from one source: the Phase C graph manifest,
produced by `vk_dispatch manifest` from the validated command graph in
the metal-inference tree (branch `feat/vulkan-int4-phase-c`). The two
checked-in manifests cover a single-layer decode (15 nodes) and a
two-layer decode (26 nodes). The node count follows the graph builder's
shape exactly: 4 + 11 nodes per layer, so 15 for one layer and 26 for
two.

Each manifest node carries its index, label, layer, shader name, INT4
weight format, SPIR-V byte size, descriptor binding count, buffer byte
sizes, push-constant bytes, spec constants, workgroups, and a validated
flag. The manifest also carries the model dimensions (hidden 3072,
intermediate 8192, 24 Q heads over 8 KV heads, head dimension 128,
vocabulary 32000) and an execution block that records the one fact that
matters most: `dispatched: false`, state `NOT_EXECUTED`, reason
`BLOCKED`. No Vulkan device exists on the machine that generated the
manifest, so no dispatch, no GPU readback, and no numerical comparison
against the CPU oracle has happened. The interface displays that state
in the top bar, in the inspector, and in the telemetry dock, and it
never implies otherwise.

The synthesis engine turns the manifest into a typed UI schema, and the
renderers consume the schema. Nothing in the scene is invented: node
positions, edge curves, colors, radii, and totals all derive from the
manifest through the engine. The one deliberate decoration is the flow
particles, small points that travel along the real execution edges.
They carry no telemetry, they encode no measurement, and the interface
says so next to the inspector. The starfield, the circuit floor, and the
core's particle shell are environment, not data.

## The scene

The composition follows a strict hierarchy. The embedding node is not
one module among others; it is the reactor at the center of the whole
environment. A custom fresnel shader shell (GLSL in the WebGL renderer,
WGSL in the WebGPU renderer) wraps a bright inner sphere, three torus
rings tilt around it at different angles and rotate slowly in opposite
directions, and a shell of several hundred particles orbits it. The
core dominates the frame from the opening camera angle, and every other
element is arranged relative to it.

Each transformer layer becomes a ring of eleven modules around the
core, offset half a step per layer so the labels of adjacent rings
interleave instead of stacking. The tail nodes (final norm, logits,
argmax) form their own outer arc. Node color is a type signature, not a
decoration: cyan for a plain validated node, violet for a node that
carries INT4 weights, gold for argmax. Node size follows role: the core
is far larger than any module, argmax is larger than a standard module.

Execution order is drawn as curved tubes, not straight lines. Each edge
is a quadratic bezier arc lifted out of the ring plane, rendered as a
tube with an additive material, so the flow reads as luminous cable
rather than a diagram connector. Residual skips are violet tubes on the
same construction, following the builder's residual data flow (the
embedding output into the attention residual, and the attention output
into the feed-forward residual). The tubes are geometry, not lines: they
have volume, they catch the bloom pass, and they hold their shape from
any orbit angle.

The environment gives the scene depth. Concentric circuit rings and an
instanced tick field lie on a floor plane below the graph, a faint grid
extends past them, a starfield surrounds the whole volume, and
exponential fog dims the far side. A point light sits at the core and
the node materials are lit, so the modules shade as real objects
instead of flat icons.

## The synthesis engine

`ocaml/karp` is the synthesis engine. It is a small OCaml program,
stdlib only: it carries its own minimal JSON parser because no JSON
library is installed in the OCaml environment on this machine. It reads
a manifest, validates it, computes the layout, and writes the typed UI
schema.

Validation is strict and it reports every failure, not just the first.
The engine checks that the node count matches the array length and the
4 + 11·layers shape, that every node index matches its position, that
labels are non-empty, that layers are in range, that every weight
format is one of the three known INT4 schemes (A signed per-row, B
offset-7.5 per-group-32, C signed per-group-64) or none, that byte
counts are non-negative, and that every node is validated. A tampered
manifest — a node count that does not match, an unknown format, an
unvalidated node — is rejected with exit code 2 and the failures listed
on stderr. No schema is written for a manifest that fails.

The layout math is the engine's central job. It places the embedding
node at the origin, lays each layer's eleven nodes on a ring whose
radius grows with the layer, places the tail nodes on an outer arc, and
computes the bezier control point for every edge by lifting the edge
midpoint out of the ring plane. The schema records, per node, the
position, color, radius, SPIR-V size, buffer total, and validated flag;
per edge, the endpoints, the kind (order or skip), and the control
point; and at the top level, the SPIR-V and buffer totals and the format
distribution. The output is deterministic: running the engine twice on
the same manifest produces byte-identical schemas.

The engine's tests live in `tests/`. `run.sh` builds the engine, runs
it on both checked-in manifests, checks determinism, runs an
independent Python cross-check that reimplements the layout and control
math from scratch and diffs every position, control point, color,
radius, and total, and runs a negative test that confirms a tampered
manifest is rejected. All of it passes on this machine.

## The WebGL renderer

`index.html` is the verified renderer. It is a single self-contained
file: Three.js r149 (UMD build, MIT upstream) and the r149
postprocessing modules (EffectComposer, RenderPass, ShaderPass,
UnrealBloomPass, and their dependencies) are inlined, as are both
manifests and both schemas. It opens with no network dependency.

The renderer builds a real scene graph: a perspective camera with a
custom orbit control (drag to orbit, wheel to zoom, damped), a scene
with fog, an ambient light and a point light at the core, standard
materials with emissive on the modules, the fresnel shader shell on the
core, tube geometry on the edges, instanced ticks on the circuit floor,
and a grid. The UnrealBloomPass runs over the whole frame through the
EffectComposer, which is what gives the core and the tubes their glow
instead of a painted halo. Flow particles travel along the real edge
curves, their positions sampled from the same bezier geometry the tubes
use. Node labels are HTML elements projected from the scene each frame,
clamped to the viewport and staggered so adjacent labels do not collide.

Clicking a node raycasts against the scene and opens it in the
inspector, which shows the node's index, label, layer, shader, SPIR-V
module and byte size, INT4 format, descriptor bindings, buffer bytes,
push constants, spec constants, workgroups, validated status, and
execution state. Two nodes carry divergence notes: the rope node, where
the port rotates each K pair once while the Metal source rotates it
inside the per-Q-head loop, and the softmax node, where causality lives
only in the length-plus-zero-tail because the Metal causal mask is a
no-op as written. Both divergences are intentional, regression-tested in
the metal-inference tree, and the inspector says so.

The layer toggle switches between the 15-node and 26-node graphs. The
renderer consumes the OCaml schema for positions, colors, radii, and
edge control points; the inline layout math remains as a fallback if a
schema is absent, kept identical to the engine's math.

## The WebGPU renderer

`webgpu.html` is the second renderer. It uses the raw WebGPU API and
WGSL shaders, no libraries: the same scene (fresnel core, lit node
spheres, bezier tubes, halo rings, circuit rings), the same schema, the
same inspector and telemetry dock, the same orbit camera, and analytic
ray-sphere picking instead of a raycaster. Its shaders are the WGSL
counterparts of the WebGL renderer's GLSL: a fresnel mode for the core
shell and a lambert mode with an emissive term for the modules, with
additive blending on the shell, the tubes, and the rings.

This renderer is built, not verified, on this machine. The Chromium on
this VM exposes `navigator.gpu` but returns no adapter in any tested
flag combination, so the page cannot execute its pipelines here. It
detects that honestly: it shows a fallback card that names the missing
adapter, states that nothing about the page is verified on this
machine, and points at the WebGL engine as the verified path. Its
JavaScript syntax-checks clean and its fallback behavior, inspector,
telemetry dock, and layer toggle were checked headless with zero page
errors. Actual rendering verification — the core, tubes, and nodes
drawing, and picking working — is a Jetson step, documented in
`JETSON.md`.

## The telemetry dock

The bottom dock is fed by the same manifest as the scene. It shows the
execution state, the manifest source and dimensions, a bar for every
node whose height is the log of that node's total buffer bytes (colored
by format, gold for argmax), and the manifest totals: node count,
validated count, total SPIR-V bytes, total buffer bytes, and the format
distribution. The bars are data, not decoration; hovering a bar names
the node and its byte total.

## Files

- `index.html` — the WebGL engine, self-contained, the verified
  deliverable. Rebuilt by `build.sh`; do not edit by hand.
- `index.template.html` — the WebGL engine source template. The build
  substitutes the Three.js library, the postprocessing bundle, the
  manifests, and the schemas into it.
- `webgpu.html` — the WebGPU renderer, self-contained. Rebuilt by
  `build.sh`; do not edit by hand.
- `webgpu.template.html` — the WebGPU renderer source template.
- `ocaml/` — the synthesis engine (`json.ml`, `karp.ml`, `main.ml`,
  `Makefile`). Build with `make -C ocaml karp`.
- `manifests/` — the two checked-in Phase C graph manifests.
- `schemas/` — the typed UI schemas the engine emits for them.
- `vendor/` — Three.js r149 UMD build, the bundled postprocessing
  modules, and the original r149 jsm sources the bundle was converted
  from.
- `tests/` — the engine test runner and the independent Python
  cross-check.
- `archive/v1-canvas2d.template.html` — the first visualizer, hand-rolled
  Canvas 2D with no library. Kept as a record of the iteration; it is
  superseded and is not built.
- `shot-desktop.png`, `shot-2layers.png` — headless renders of the
  WebGL engine at both layer counts.
- `shot-webgpu-fallback.png` — the WebGPU page's honest fallback on
  this machine.
- `build.sh` — the deterministic build: regenerate schemas, assemble
  both pages. Re-running it reproduces byte-identical outputs.
- `STATUS.md` — what is verified and what is not, as plain facts.
- `JETSON.md` — the handoff for the Jetson side: dispatch, manifest
  re-export, WebGPU verification.
- `WATERMARK.md` — the hash-chained manifest of the tree.

## Building

Run `./build.sh`. It finds the OCaml toolchain (PATH, then the local
ocaml-env), builds the engine, regenerates both schemas, and assembles
both pages. Run `sh tests/run.sh` for the engine tests. The pages open
directly from disk: no server, no network, no install step.

## What is not done

Live execution animation is gated on demonstrated Vulkan dispatch, and
dispatch is blocked on a usable Vulkan device; the Jetson is the
machine that can provide one. The WebGPU renderer is unverified until
it runs on a machine with an adapter. The manifest's execution block
still says NOT_EXECUTED, and it stays that way until a dispatch receipt
exists to replace it. None of that is a defect in this tree; it is the
boundary the tree is honest about. See `STATUS.md` and `JETSON.md`.
