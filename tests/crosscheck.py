#!/usr/bin/env python3
"""Independent cross-check of the OCaml-emitted schema against the manifest.

Reimplements the frontend's layoutPos + tube() control-point math from
scratch in Python and diffs every node position, edge control point,
color, radius and total against the schema the OCaml engine emitted.
Tolerance 1e-4 (the schema prints floats to 6 decimals).
"""
import json
import math
import sys

TOL = 1e-4


def layout_pos(layers, i, layer):
    if i == 0:
        return (0.0, 0.0, 0.0)
    tail_start = 1 + 11 * layers
    if i >= tail_start:
        r = 175 + layers * 120 + 55
        a = [-math.pi / 2, math.pi / 12, math.pi * 0.75][i - tail_start]
        z = 30 * math.sin(a * 2)
        return (r * math.cos(a), r * math.sin(a) * 0.9, z)
    L = layer
    j = (i - 1) % 11
    r = 175 + L * 120
    a = j * (math.pi * 2 / 11) - math.pi / 2 + L * (0.28 + math.pi / 11)
    z = 34 * math.sin(a * 2 + L)
    return (r * math.cos(a), r * math.sin(a) * 0.9, z)


def control(pa, pb):
    mx = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2)
    dx, dy, dz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
    ln = math.sqrt(dx * dx + dy * dy + dz * dz)
    ml = math.sqrt(mx[0] ** 2 + mx[1] ** 2 + mx[2] ** 2)
    nx, ny, nz = (mx[0] / ml, mx[1] / ml, mx[2] / ml) if ml else (0, 1, 0)
    s = 26 + ln * 0.14
    lift = (nx * s, ny * s + 30, nz * s + 18)
    return (mx[0] + lift[0], mx[1] + lift[1], mx[2] + lift[2])


def color_of(n):
    if n["shader"] == "argmax":
        return "#ffc46b"
    if n["weight_format"] != "none":
        return "#b07cff"
    return "#37e6ff"


def radius_of(n):
    if n["index"] == 0:
        return 48.0
    if n["shader"] == "argmax":
        return 11.0
    return 7.0


def close(a, b):
    return all(abs(x - y) <= TOL for x, y in zip(a, b))


def main():
    schema_path, manifest_path, layers = sys.argv[1], sys.argv[2], int(sys.argv[3])
    schema = json.load(open(schema_path))
    manifest = json.load(open(manifest_path))
    fails = []

    assert schema["schema_version"] == 1, "schema_version"
    assert schema["source"]["layers"] == layers, "layers"
    assert schema["source"]["node_count"] == manifest["node_count"], "node_count"
    assert schema["source"]["node_count"] == 4 + 11 * layers, "node count formula"
    nodes = manifest["nodes"]
    snodes = schema["nodes"]
    assert len(snodes) == len(nodes), "node list length"

    for n, sn in zip(nodes, snodes):
        assert sn["index"] == n["index"] and sn["label"] == n["label"], n["label"]
        want_pos = layout_pos(layers, n["index"], n["layer"])
        if not close(sn["position"], want_pos):
            fails.append(f"node {n['label']} position {sn['position']} != {want_pos}")
        if sn["color"] != color_of(n):
            fails.append(f"node {n['label']} color {sn['color']} != {color_of(n)}")
        if abs(sn["radius"] - radius_of(n)) > TOL:
            fails.append(f"node {n['label']} radius {sn['radius']} != {radius_of(n)}")
        if sn["spv_bytes"] != n["spv_bytes"]:
            fails.append(f"node {n['label']} spv_bytes mismatch")
        if sn["buffer_bytes_total"] != sum(n["buffer_bytes"]):
            fails.append(f"node {n['label']} buffer total mismatch")
        if sn["validated"] is not True:
            fails.append(f"node {n['label']} not validated")

    want_edges = [(i, i + 1, "order") for i in range(len(nodes) - 1)]
    for L in range(layers):
        s = 1 + 11 * L
        src = 0 if L == 0 else 1 + 11 * (L - 1) + 10
        want_edges += [(src, s + 6, "skip"), (s + 6, s + 10, "skip")]
    sedges = schema["edges"]
    assert len(sedges) == len(want_edges), f"edge count {len(sedges)} != {len(want_edges)}"
    for (a, b, kind), se in zip(want_edges, sedges):
        if (se["from"], se["to"], se["kind"]) != (a, b, kind):
            fails.append(f"edge order mismatch: {se} != {(a, b, kind)}")
            continue
        pa = layout_pos(layers, a, nodes[a]["layer"])
        pb = layout_pos(layers, b, nodes[b]["layer"])
        if not close(se["control"], control(pa, pb)):
            fails.append(f"edge {a}->{b} control {se['control']} != {control(pa, pb)}")

    tot = schema["totals"]
    if tot["spv_total"] != sum(n["spv_bytes"] for n in nodes):
        fails.append("spv_total mismatch")
    if tot["buffer_total"] != sum(sum(n["buffer_bytes"]) for n in nodes):
        fails.append("buffer_total mismatch")
    fmt = {}
    for n in nodes:
        fmt[n["weight_format"]] = fmt.get(n["weight_format"], 0) + 1
    if tot["formats"] != fmt:
        fails.append(f"formats {tot['formats']} != {fmt}")

    if fails:
        print(f"CROSSCHECK FAIL ({len(fails)}):")
        for f in fails:
            print(" -", f)
        sys.exit(1)
    print(f"crosscheck OK: {len(nodes)} nodes, {len(want_edges)} edges, layers={layers}")


main()
