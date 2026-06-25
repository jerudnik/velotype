#!/usr/bin/env bash
set -euo pipefail

fixture=${1:-docs/feasibility/probe.md}
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

python tools/feasibility/block_layer_probe.py identity "$fixture" > "$workdir/identity.json"
python - "$workdir/identity.json" "$workdir/sidecar.json" <<'PY'
import json, sys
blocks=json.load(open(sys.argv[1]))
para=next(v for v in blocks.values() if v['kind']=='paragraph' and 'substantive claim' in v['text'])
sidecar={'annotations':[{'id':'ann-1','fingerprint':para['fingerprint'],'quoted':para['text'],'note':'Needs clearer evidence chain.'}]}
open(sys.argv[2],'w').write(json.dumps(sidecar,indent=2))
PY
python - "$fixture" "$workdir/probe-edited.md" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]).read_text()
p=p.replace('This paragraph makes a substantive claim that needs evidence', 'This revised paragraph makes a substantive claim that still needs evidence')
parts=p.split('\n\n')
if len(parts) >= 7:
    parts[6], parts[4] = parts[4], parts[6]
Path(sys.argv[2]).write_text('\n\n'.join(parts))
PY
python tools/feasibility/block_layer_probe.py reconcile "$workdir/sidecar.json" "$workdir/probe-edited.md" > "$workdir/reconcile.json"
python tools/feasibility/block_layer_probe.py citations "$fixture" > "$workdir/citations.json"
python tools/feasibility/block_layer_probe.py export-layers omit "$fixture" > "$workdir/export-omit.md"
python tools/feasibility/block_layer_probe.py export-layers render "$fixture" > "$workdir/export-render.md"
python tools/feasibility/block_layer_probe.py export-layers preserve "$fixture" > "$workdir/export-preserve.md"
if python tools/feasibility/block_layer_probe.py export-layers fail "$fixture" > "$workdir/export-fail.md" 2> "$workdir/export-fail.err"; then
  echo 'expected fail policy to reject layered fixture' >&2
  exit 1
fi
python - "$workdir" <<'PY'
import json, sys
from pathlib import Path
w=Path(sys.argv[1])
identity=json.load(open(w/'identity.json'))
reconcile=json.load(open(w/'reconcile.json'))
citations=json.load(open(w/'citations.json'))
omit=(w/'export-omit.md').read_text()
render=(w/'export-render.md').read_text()
assert len(identity) == 7, len(identity)
assert reconcile['results'][0]['status'] in {'exact-fingerprint','fuzzy-token'}
assert {'@smith2020','@doe-2021','@miller2022'} <= set(citations)
assert 'velotype:' not in omit
assert '[!NOTE]' in render
print('feasibility probe passed')
print(f"blocks={len(identity)} reconciliation={reconcile['results'][0]['status']} citations={len(citations)}")
PY
