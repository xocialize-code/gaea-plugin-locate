#!/bin/zsh
# The plugin against in-process MLXServeEngine: boxes found on the signed bundle the way Gaea runs it
# (gaea-plugin-check: launch under the launch requirement, configure, prepare, run) and through locate-inproc with the
# lane configuration and the request the worker uses. Each pair must be the same list of boxes, number for number.
#
#   scripts/golden.sh <out-dir>     (after scripts/build-plugin.sh)
#
# Cases, on Tests/Fixtures/fox.png:
# - "the fox", one box, on int8 and on int4: a box that covers most of the picture's middle;
# - "the fox's ears", up to four boxes: one small box for each ear, in the model's order (Gaea sorts by score);
# - "a bicycle": nothing there, an empty list.
set -uo pipefail
ROOT=${0:A:h:h}
cd $ROOT
OUT=${1:?out dir}; mkdir -p $OUT
B=$ROOT/dist/locate.gaeaplugin
FOX=$ROOT/Tests/Fixtures/fox.png
MODELS=${CHECK_MODELS_ROOT:-/Volumes/DEV_VOL1/Models}
SWIFTPM=(-c release --build-system swiftbuild)
xcrun swift build $SWIFTPM --product locate-inproc > /dev/null && xcrun swift build -c release --product gaea-plugin-check > /dev/null
INPROC=$(xcrun swift build $SWIFTPM --show-bin-path)/locate-inproc; CHECK=$(xcrun swift build -c release --show-bin-path)/gaea-plugin-check
LOG=$OUT/golden.log; : > $LOG
pass=0; fail=0
say() { print -r -- "$*" | tee -a $LOG }
say "# Locate golden check $(date -u +%FT%TZ): $(python3 -c "import json; m=json.load(open('$B/Contents/Resources/manifest.json')); print(m['id'], m['version'])")"
# The `boxes` value of the session's result line.
gppboxes() { python3 - $1 <<'PY'
import json, sys
for line in open(sys.argv[1]):
    i = line.find('{')
    if i < 0: continue
    try: m = json.loads(line[i:])
    except Exception: continue
    if m.get('type') == 'result':
        print(json.dumps([o['value'] for o in m['outputs'] if o['name'] == 'boxes'][0])); break
PY
}

# case <name> <lane> <count> <prompt> <python check over b, the list of boxes>
case_() {
  local name=$1 lane=$2 count=$3 prompt=$4 want=$5
  $CHECK $B --operation image.locate --model qwen3-vl-locate --lane $lane --params "{\"count\":$count}" --input "image=$FOX" \
    --text "prompt=$prompt" --models-root "$MODELS" --budget 64000000000 --timeout 900 --session $OUT/$name.gpp > $OUT/$name-gpp.log 2>&1
  gppboxes $OUT/$name.gpp > $OUT/$name-gpp.json
  $INPROC --image $FOX --prompt "$prompt" --count $count --lane $lane --runs 1 --models-root "$MODELS" --out $OUT/$name-inproc.json 2>> $LOG | tail -1 > $OUT/$name-inproc.line
  say "      $name: over GPP $(grep -o 'ran in [0-9.]* s' $OUT/$name-gpp.log | head -1); boxes $(cat $OUT/$name-gpp.json | cut -c1-300)"
  if python3 -c "
import json, sys
a = json.load(open('$OUT/$name-gpp.json')); b = json.load(open('$OUT/$name-inproc.json'))
assert a == b, ('differ', a, b)
assert all(0 <= x['x'] and 0 <= x['y'] and x['width'] > 0 and x['height'] > 0 and x['x'] + x['width'] <= 1.0001 and x['y'] + x['height'] <= 1.0001 for x in b), b
assert len(b) <= $count
b = a
assert $want, b" >> $LOG 2>&1; then pass=$((pass+1)); say "PASS  $name: the same boxes over GPP and in-process, and as expected"
  else fail=$((fail+1)); say "FAIL  $name (see the log)"; fi
}

case_ fox int8 1 "the fox" "len(b) == 1 and b[0]['width'] * b[0]['height'] > 0.2 and b[0]['label'] == 'the fox' and 0 < b[0]['score'] <= 1"
case_ fox-int4 int4 1 "the fox" "len(b) == 1 and b[0]['width'] * b[0]['height'] > 0.2"
# The worker returns the model's order; Gaea's MESKit sorts by score.
case_ ears int8 4 "the fox's ears" "len(b) >= 2 and all(x['width'] * x['height'] < 0.2 and 0 < x['score'] <= 1 for x in b)"
case_ nothing int8 1 "a bicycle" "b == []"

for s in $OUT/*.gpp; do
  if python3 ${GAEA_SPEC_ROOT:-$ROOT/../gaea-mes-media-server}/tools/validate.py --transcript $s >> $LOG 2>&1; then pass=$((pass+1)); say "PASS  ${s:t} passes validate.py"
  else fail=$((fail+1)); say "FAIL  ${s:t} fails validate.py"; fi
done
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
