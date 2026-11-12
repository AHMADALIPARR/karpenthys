(* Karpenthys synthesis engine: validate a Phase C graph manifest and emit
   the typed UI schema the renderers consume.

   The layout math here is the same math the WebGL frontend used inline:
   radial rings per layer, tail ring for the final nodes, bezier control
   points lifted out of the ring plane. The engine is now the single
   source of that geometry; the frontend consumes the schema. *)

open Json

exception Validation_error of string list

let pi = 4.0 *. atan 1.0

let known_formats =
  [ "none"; "A(signed,per-row)"; "B(offset7.5,group32)"; "C(signed,group64,flat)" ]

type node = {
  index : int;
  label : string;
  layer : int;
  shader : string;
  weight_format : string;
  spv_bytes : int;
  buffer_bytes : int list;
  binding_count : int;
  validated : bool;
}

type manifest = {
  generator : string;
  manifest_version : int;
  layers : int;
  node_count : int;
  execution_state : string;
  nodes : node list;
}

(* ---- manifest parsing + validation (failures collected, all reported) ---- *)

let parse_manifest v =
  let errors = ref [] in
  let fail msg = errors := msg :: !errors in
  let req_int nv k =
    try field_int nv k
    with Field_error m ->
      fail ("node field: " ^ m);
      0
  in
  let req_str nv k =
    try field_string nv k
    with Field_error m ->
      fail ("node field: " ^ m);
      ""
  in
  let req_bool nv k =
    try field_bool nv k
    with Field_error m ->
      fail ("node field: " ^ m);
      false
  in
  let top_int k =
    try field_int v k
    with Field_error m ->
      fail m;
      0
  in
  let top_str k =
    try field_string v k
    with Field_error m ->
      fail m;
      ""
  in
  let layers = top_int "layers" in
  let node_count = top_int "node_count" in
  let nodes =
    try
      List.map
        (fun nv ->
          let buffer_bytes =
            try List.map as_int (field_array nv "buffer_bytes")
            with Field_error m ->
              fail ("node field: " ^ m);
              []
          in
          {
            index = req_int nv "index";
            label = req_str nv "label";
            layer = req_int nv "layer";
            shader = req_str nv "shader";
            weight_format = req_str nv "weight_format";
            spv_bytes = req_int nv "spv_bytes";
            buffer_bytes;
            binding_count = req_int nv "binding_count";
            validated = req_bool nv "validated";
          })
        (field_array v "nodes")
    with Field_error m ->
      fail m;
      []
  in
  if layers < 1 then fail "layers < 1";
  if node_count <> List.length nodes then
    fail
      (Printf.sprintf "node_count %d <> nodes array length %d" node_count
         (List.length nodes));
  if node_count <> 4 + (11 * layers) then
    fail
      (Printf.sprintf "node_count %d <> 4 + 11*%d for the Phase C graph shape"
         node_count layers);
  List.iteri
    (fun i n ->
      if n.index <> i then
        fail (Printf.sprintf "node %d has index %d" i n.index);
      if n.label = "" then fail (Printf.sprintf "node %d has empty label" i);
      if n.layer < -1 || n.layer >= layers then
        fail (Printf.sprintf "node %d layer %d out of range" i n.layer);
      if not (List.mem n.weight_format known_formats) then
        fail
          (Printf.sprintf "node %d unknown weight_format %s" i n.weight_format);
      if n.spv_bytes < 0 then
        fail (Printf.sprintf "node %d negative spv_bytes" i);
      if List.exists (fun b -> b < 0) n.buffer_bytes then
        fail (Printf.sprintf "node %d negative buffer_bytes entry" i);
      if n.binding_count < 0 then
        fail (Printf.sprintf "node %d negative binding_count" i);
      if not n.validated then
        fail (Printf.sprintf "node %d (%s) is not validated" i n.label))
    nodes;
  let execution_state =
    try field_string (get v "execution") "state"
    with Field_error m ->
      fail m;
      ""
  in
  if !errors <> [] then raise (Validation_error (List.rev !errors));
  {
    generator = top_str "generator";
    manifest_version = top_int "manifest_version";
    layers;
    node_count;
    execution_state;
    nodes;
  }

(* ---- layout: the same math the frontend used inline ---- *)

type vec3 = float * float * float

let layout_pos layers i layer =
  if i = 0 then (0.0, 0.0, 0.0)
  else
    let tail_start = 1 + (11 * layers) in
    if i >= tail_start then
      let r = 175.0 +. (float_of_int layers *. 120.0) +. 55.0 in
      let a =
        [| (-.pi /. 2.0); pi /. 12.0; pi *. 0.75 |].(i - tail_start)
      in
      let z = 30.0 *. sin (a *. 2.0) in
      (r *. cos a, r *. sin a *. 0.9, z)
    else
      let l = layer in
      let j = (i - 1) mod 11 in
      let r = 175.0 +. (float_of_int l *. 120.0) in
      let a =
        float_of_int j *. (pi *. 2.0 /. 11.0)
        -. (pi /. 2.0)
        +. (float_of_int l *. (0.28 +. (pi /. 11.0)))
      in
      let z = 34.0 *. sin ((a *. 2.0) +. float_of_int l) in
      (r *. cos a, r *. sin a *. 0.9, z)

let vsub (ax, ay, az) (bx, by, bz) = (ax -. bx, ay -. by, az -. bz)
let vadd (ax, ay, az) (bx, by, bz) = (ax +. bx, ay +. by, az +. bz)
let vscale s (x, y, z) = (x *. s, y *. s, z *. s)
let vlen (x, y, z) = sqrt ((x *. x) +. (y *. y) +. (z *. z))
let vmid a b = vscale 0.5 (vadd a b)

let normalize (x, y, z) =
  let l = vlen (x, y, z) in
  if l = 0.0 then (0.0, 1.0, 0.0) else (x /. l, y /. l, z /. l)

(* bezier control point: midpoint lifted out of the ring plane, exactly as
   the frontend's tube() built it. *)
let control pa pb =
  let mid = vmid pa pb in
  let len = vlen (vsub pb pa) in
  let s = 26.0 +. (len *. 0.14) in
  let nx, ny, nz = normalize mid in
  let lift = (nx *. s, (ny *. s) +. 30.0, (nz *. s) +. 18.0) in
  vadd mid lift

let color_of n =
  if n.shader = "argmax" then "#ffc46b"
  else if n.weight_format <> "none" then "#b07cff"
  else "#37e6ff"

let radius_of n =
  if n.index = 0 then 48.0 else if n.shader = "argmax" then 11.0 else 7.0

(* ---- schema emission ---- *)

let vec_json (x, y, z) = Arr [ Float x; Float y; Float z ]

let emit_schema m =
  let positions = List.map (fun n -> layout_pos m.layers n.index n.layer) m.nodes in
  let pos_at i = List.nth positions i in
  let order_edges =
    List.init (m.node_count - 1) (fun i -> (i, i + 1, "order"))
  in
  let skip_edges =
    List.concat
      (List.init m.layers (fun l ->
           let s = 1 + (11 * l) in
           let src = if l = 0 then 0 else 1 + (11 * (l - 1)) + 10 in
           [ (src, s + 6, "skip"); (s + 6, s + 10, "skip") ]))
  in
  let edges = order_edges @ skip_edges in
  let edge_json (a, b, kind) =
    Obj
      [
        ("from", Int a);
        ("to", Int b);
        ("kind", Str kind);
        ("control", vec_json (control (pos_at a) (pos_at b)));
      ]
  in
  let node_json n =
    let pos = layout_pos m.layers n.index n.layer in
    Obj
      [
        ("index", Int n.index);
        ("label", Str n.label);
        ("layer", Int n.layer);
        ("shader", Str n.shader);
        ("weight_format", Str n.weight_format);
        ("color", Str (color_of n));
        ("radius", Float (radius_of n));
        ("position", vec_json pos);
        ("spv_bytes", Int n.spv_bytes);
        ("buffer_bytes_total", Int (List.fold_left ( + ) 0 n.buffer_bytes));
        ("validated", Bool n.validated);
      ]
  in
  let spv_total = List.fold_left (fun acc n -> acc + n.spv_bytes) 0 m.nodes in
  let buffer_total =
    List.fold_left
      (fun acc n -> acc + List.fold_left ( + ) 0 n.buffer_bytes)
      0 m.nodes
  in
  let fmt_counts =
    List.fold_left
      (fun acc n ->
        let k = n.weight_format in
        match List.assoc_opt k acc with
        | Some c -> (k, c + 1) :: List.remove_assoc k acc
        | None -> (k, 1) :: acc)
      [] m.nodes
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  in
  Obj
    [
      ("schema_version", Int 1);
      ("generator", Str "karp ocaml synthesis engine");
      ( "source",
        Obj
          [
            ("generator", Str m.generator);
            ("manifest_version", Int m.manifest_version);
            ("layers", Int m.layers);
            ("node_count", Int m.node_count);
            ("execution_state", Str m.execution_state);
          ] );
      ("nodes", Arr (List.map node_json m.nodes));
      ("edges", Arr (List.map edge_json edges));
      ( "totals",
        Obj
          [
            ("spv_total", Int spv_total);
            ("buffer_total", Int buffer_total);
            ( "formats",
              Obj (List.map (fun (k, c) -> (k, Int c)) fmt_counts) );
          ] );
    ]

let edge_count m = (m.node_count - 1) + (2 * m.layers)
