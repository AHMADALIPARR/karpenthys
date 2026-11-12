#!/bin/sh
# Karpenthys OCaml engine tests: build, run on both checked-in manifests,
# determinism (run twice, byte-identical), independent Python cross-check.
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/workspace/.tools/ocaml-env/bin:$PATH"
make -C ocaml karp
./ocaml/karp manifests/graph_manifest_1layer.json /tmp/karp_schema1.json
./ocaml/karp manifests/graph_manifest_2layers.json /tmp/karp_schema2.json
./ocaml/karp manifests/graph_manifest_1layer.json /tmp/karp_schema1b.json
cmp /tmp/karp_schema1.json /tmp/karp_schema1b.json && echo "determinism OK (1-layer)"
python3 tests/crosscheck.py /tmp/karp_schema1.json manifests/graph_manifest_1layer.json 1
python3 tests/crosscheck.py /tmp/karp_schema2.json manifests/graph_manifest_2layers.json 2
# negative test: a tampered manifest (node count wrong) must fail, exit 2
python3 -c "
import json
m = json.load(open('manifests/graph_manifest_1layer.json'))
m['node_count'] = 99
json.dump(m, open('/tmp/karp_bad.json', 'w'))
"
if ./ocaml/karp /tmp/karp_bad.json /tmp/karp_bad_out.json 2>/tmp/karp_bad_err.txt; then
  echo "NEGATIVE TEST FAILED: tampered manifest accepted"; exit 1
else
  echo "negative test OK: tampered manifest rejected:"
  cat /tmp/karp_bad_err.txt
fi
echo "KARP TESTS OK"
