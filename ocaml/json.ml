(* Minimal JSON parser and printer, stdlib only. No yojson on this box,
   so the engine carries its own. *)

type value =
  | Null
  | Bool of bool
  | Int of int
  | Float of float
  | Str of string
  | Arr of value list
  | Obj of (string * value) list

exception Parse_error of string

type parser = { s : string; mutable i : int }

let mk s = { s; i = 0 }

let err p msg = raise (Parse_error (Printf.sprintf "%s at offset %d" msg p.i))

let peek p = if p.i < String.length p.s then Some p.s.[p.i] else None
let next p = match peek p with Some c -> p.i <- p.i + 1; Some c | None -> None

let rec skip_ws p =
  match peek p with
  | Some (' ' | '\t' | '\n' | '\r') -> p.i <- p.i + 1; skip_ws p
  | _ -> ()

let expect p c =
  match next p with
  | Some d when d = c -> ()
  | _ -> err p (Printf.sprintf "expected '%c'" c)

let parse_literal p lit v =
  let n = String.length lit in
  if p.i + n <= String.length p.s && String.sub p.s p.i n = lit then (p.i <- p.i + n; v)
  else err p ("expected " ^ lit)

let hex_val c =
  match c with
  | '0' .. '9' -> Char.code c - Char.code '0'
  | 'a' .. 'f' -> Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' -> Char.code c - Char.code 'A' + 10
  | _ -> -1

let utf8_of_cp cp =
  if cp < 0x80 then String.make 1 (Char.chr cp)
  else if cp < 0x800 then
    let b = Bytes.create 2 in
    Bytes.set b 0 (Char.chr (0xC0 lor (cp lsr 6)));
    Bytes.set b 1 (Char.chr (0x80 lor (cp land 0x3F)));
    Bytes.to_string b
  else
    let b = Bytes.create 3 in
    Bytes.set b 0 (Char.chr (0xE0 lor (cp lsr 12)));
    Bytes.set b 1 (Char.chr (0x80 lor ((cp lsr 6) land 0x3F)));
    Bytes.set b 2 (Char.chr (0x80 lor (cp land 0x3F)));
    Bytes.to_string b

let parse_string p =
  expect p '"';
  let buf = Buffer.create 32 in
  let rec loop () =
    match next p with
    | None -> err p "unterminated string"
    | Some '"' -> Buffer.contents buf
    | Some '\\' -> (
        match next p with
        | Some '"' -> Buffer.add_char buf '"'; loop ()
        | Some '\\' -> Buffer.add_char buf '\\'; loop ()
        | Some '/' -> Buffer.add_char buf '/'; loop ()
        | Some 'b' -> Buffer.add_char buf '\b'; loop ()
        | Some 'f' -> Buffer.add_char buf '\012'; loop ()
        | Some 'n' -> Buffer.add_char buf '\n'; loop ()
        | Some 'r' -> Buffer.add_char buf '\r'; loop ()
        | Some 't' -> Buffer.add_char buf '\t'; loop ()
        | Some 'u' ->
            let h () =
              match next p with
              | Some c ->
                  let v = hex_val c in
                  if v < 0 then err p "bad \\u escape" else v
              | None -> err p "bad \\u escape"
            in
            let cp = (((h () * 16) + h ()) * 16 + h ()) * 16 + h () in
            Buffer.add_string buf (utf8_of_cp cp);
            loop ()
        | _ -> err p "bad escape")
    | Some c -> Buffer.add_char buf c; loop ()
  in
  loop ()

let parse_number p =
  let start = p.i in
  let rec loop () =
    match peek p with
    | Some ('0' .. '9' | '-' | '+' | '.' | 'e' | 'E') -> p.i <- p.i + 1; loop ()
    | _ -> ()
  in
  loop ();
  let tok = String.sub p.s start (p.i - start) in
  if tok = "" then err p "expected number";
  if String.contains tok '.' || String.contains tok 'e' || String.contains tok 'E' then
    Float (float_of_string tok)
  else Int (int_of_string tok)

let rec parse_value p =
  skip_ws p;
  match peek p with
  | Some '{' -> parse_obj p
  | Some '[' -> parse_arr p
  | Some '"' -> Str (parse_string p)
  | Some 't' -> parse_literal p "true" (Bool true)
  | Some 'f' -> parse_literal p "false" (Bool false)
  | Some 'n' -> parse_literal p "null" Null
  | Some _ -> parse_number p
  | None -> err p "unexpected end of input"

and parse_arr p =
  expect p '[';
  skip_ws p;
  match peek p with
  | Some ']' ->
      p.i <- p.i + 1;
      Arr []
  | _ ->
      let rec loop acc =
        let v = parse_value p in
        skip_ws p;
        match next p with
        | Some ',' -> loop (v :: acc)
        | Some ']' -> Arr (List.rev (v :: acc))
        | _ -> err p "expected ',' or ']' in array"
      in
      loop []

and parse_obj p =
  expect p '{';
  skip_ws p;
  match peek p with
  | Some '}' ->
      p.i <- p.i + 1;
      Obj []
  | _ ->
      let rec loop acc =
        skip_ws p;
        let k = parse_string p in
        skip_ws p;
        expect p ':';
        let v = parse_value p in
        skip_ws p;
        match next p with
        | Some ',' -> loop ((k, v) :: acc)
        | Some '}' -> Obj (List.rev ((k, v) :: acc))
        | _ -> err p "expected ',' or '}' in object"
      in
      loop []

let parse s =
  let p = mk s in
  let v = parse_value p in
  skip_ws p;
  if p.i <> String.length p.s then err p "trailing characters";
  v

(* ---- printer: compact, deterministic, insertion-ordered keys ---- *)

let escape_string s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | '\t' -> Buffer.add_string buf "\\t"
      | '\b' -> Buffer.add_string buf "\\b"
      | '\012' -> Buffer.add_string buf "\\f"
      | c when Char.code c < 0x20 ->
          Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buf c)
    s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let rec print buf = function
  | Null -> Buffer.add_string buf "null"
  | Bool true -> Buffer.add_string buf "true"
  | Bool false -> Buffer.add_string buf "false"
  | Int n -> Buffer.add_string buf (string_of_int n)
  | Float f -> Buffer.add_string buf (Printf.sprintf "%.6f" f)
  | Str s -> Buffer.add_string buf (escape_string s)
  | Arr vs ->
      Buffer.add_char buf '[';
      List.iteri
        (fun i v ->
          if i > 0 then Buffer.add_char buf ',';
          print buf v)
        vs;
      Buffer.add_char buf ']'
  | Obj kvs ->
      Buffer.add_char buf '{';
      List.iteri
        (fun i (k, v) ->
          if i > 0 then Buffer.add_char buf ',';
          Buffer.add_string buf (escape_string k);
          Buffer.add_char buf ':';
          print buf v)
        kvs;
      Buffer.add_char buf '}'

let to_string v =
  let buf = Buffer.create 256 in
  print buf v;
  Buffer.contents buf

(* ---- field access helpers ---- *)

exception Field_error of string

let obj_fields = function
  | Obj kvs -> kvs
  | _ -> raise (Field_error "not an object")

let get v k =
  match List.assoc_opt k (obj_fields v) with
  | Some x -> x
  | None -> raise (Field_error ("missing field: " ^ k))

let as_string = function
  | Str s -> s
  | _ -> raise (Field_error "not a string")

let as_int = function
  | Int n -> n
  | Float f -> int_of_float f
  | _ -> raise (Field_error "not an int")

let as_float = function
  | Float f -> f
  | Int n -> float_of_int n
  | _ -> raise (Field_error "not a number")

let as_bool = function
  | Bool b -> b
  | _ -> raise (Field_error "not a bool")

let as_array = function
  | Arr vs -> vs
  | _ -> raise (Field_error "not an array")

let field_string v k = as_string (get v k)
let field_int v k = as_int (get v k)
let field_bool v k = as_bool (get v k)
let field_array v k = as_array (get v k)
