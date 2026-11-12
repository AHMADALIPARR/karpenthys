(* karp: validate a Phase C graph manifest, emit the typed UI schema.
   usage: karp <manifest.json> <schema.json> *)

let read_all path =
  let ch = open_in_bin path in
  let n = in_channel_length ch in
  let s = really_input_string ch n in
  close_in ch;
  s

let write_all path s =
  let ch = open_out_bin path in
  output_string ch s;
  close_out ch

let () =
  if Array.length Sys.argv <> 3 then (
    prerr_endline "usage: karp <manifest.json> <schema.json>";
    exit 2);
  let manifest_path = Sys.argv.(1) in
  let schema_path = Sys.argv.(2) in
  let text =
    try read_all manifest_path
    with Sys_error m ->
      prerr_endline ("karp: cannot read manifest: " ^ m);
      exit 2
  in
  let value =
    try Json.parse text
    with Json.Parse_error m ->
      prerr_endline ("karp: JSON: " ^ m);
      exit 2
  in
  let m =
    try Karp.parse_manifest value
    with Karp.Validation_error errs ->
      List.iter (fun e -> prerr_endline ("FAIL: " ^ e)) errs;
      exit 2
  in
  let schema = Karp.emit_schema m in
  write_all schema_path (Json.to_string schema);
  let totals = Json.get schema "totals" in
  Printf.printf "karp: %s layers=%d nodes=%d edges=%d\n" m.generator m.layers
    m.node_count (Karp.edge_count m);
  Printf.printf "karp: validated %d/%d spv_total=%d buffer_total=%d\n"
    m.node_count m.node_count
    (Json.field_int totals "spv_total")
    (Json.field_int totals "buffer_total");
  Printf.printf "karp: execution_state=%s\n" m.execution_state;
  Printf.printf "karp: wrote %s\n" schema_path
