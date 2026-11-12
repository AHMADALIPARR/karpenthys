#!/bin/sh
# Karpenthys build: regenerate the typed UI schemas with the OCaml
# synthesis engine, then assemble index.html (WebGL) and webgpu.html
# (WebGPU) from their templates. Deterministic: re-running produces
# byte-identical outputs.
set -e
cd "$(dirname "$0")"
if ! command -v ocamlopt >/dev/null 2>&1; then
  if [ -x "$HOME/workspace/.tools/ocaml-env/bin/ocamlopt" ]; then
    export PATH="$HOME/workspace/.tools/ocaml-env/bin:$PATH"
  else
    echo "build.sh: ocamlopt not found (tried PATH and ~/workspace/.tools/ocaml-env/bin)" >&2
    exit 1
  fi
fi
mkdir -p schemas
make -C ocaml karp >/dev/null
./ocaml/karp manifests/graph_manifest_1layer.json schemas/graph_schema_1layer.json
./ocaml/karp manifests/graph_manifest_2layers.json schemas/graph_schema_2layers.json
python3 - <<'PYEOF'
import pathlib
K = pathlib.Path('.')
t = (K / 'index.template.html').read_text()
three = (K / 'vendor/three.min.js').read_text().replace('</script', '<\\/script')
post = (K / 'vendor/postprocessing.js').read_text().replace('</script', '<\\/script')
m1 = (K / 'manifests/graph_manifest_1layer.json').read_text().strip()
m2 = (K / 'manifests/graph_manifest_2layers.json').read_text().strip()
s1 = (K / 'schemas/graph_schema_1layer.json').read_text().strip()
s2 = (K / 'schemas/graph_schema_2layers.json').read_text().strip()
for tok, val in [('__THREE__', three), ('__POST__', post),
                 ('__MANIFEST_1__', m1), ('__MANIFEST_2__', m2),
                 ('__SCHEMA_1__', s1), ('__SCHEMA_2__', s2)]:
    assert tok in t, tok
    t = t.replace(tok, val)
(K / 'index.html').write_text(t)
t2 = (K / 'webgpu.template.html').read_text()
for tok, val in [('__MANIFEST_1__', m1), ('__MANIFEST_2__', m2),
                 ('__SCHEMA_1__', s1), ('__SCHEMA_2__', s2)]:
    assert tok in t2, tok
    t2 = t2.replace(tok, val)
(K / 'webgpu.html').write_text(t2)
print('assembled index.html (%d bytes) + webgpu.html (%d bytes)' % (len(t), len(t2)))
PYEOF
echo "build.sh: OK"
