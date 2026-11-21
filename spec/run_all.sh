#!/bin/sh
# ANA Rule v1: remake the test files, check both implementations, then make sure the tests catch planted bugs.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mktemp -d)
python3 -I "$HERE/py/make_vectors.py" "$HERE/vectors" | tail -1
javac -nowarn -d "$OUT" "$HERE/java/Engine.java" "$HERE/java/AnaRule.java" "$HERE/java/RunVectors.java" 2>/dev/null
(cd "$OUT" && java -cp "$OUT" RunVectors "$HERE/vectors" | tail -1)

plant() {   # $1 = text to replace, $2 = replacement, $3 = label
  M=$(mktemp -d)
  cp "$HERE/java/Engine.java" "$HERE/java/RunVectors.java" "$M/"
  python3 -I -c "import sys;s=open(sys.argv[1]).read();assert sys.argv[2] in s;open(sys.argv[3],'w').write(s.replace(sys.argv[2],sys.argv[4],1))" \
    "$HERE/java/AnaRule.java" "$1" "$M/AnaRule.java" "$2"
  javac -nowarn -d "$M" "$M"/*.java 2>/dev/null
  if (cd "$M" && java -cp "$M" RunVectors "$HERE/vectors" > /dev/null 2>&1); then echo "NOT CAUGHT: $3"; exit 1; else echo "caught: $3"; fi
}
plant 'if (highS(s.sig)) return v("HIGH_S", "");' '' "no high-S check"
plant 'if (!prev.equals(head)) {' 'if (false) {' "prev link ignored"
plant 'if (lt.equals("statia") && !tier.equals("statia"))' 'if (false)' "no tier gate"
plant 'if (seq >= intOr(permit.kv.get("permit|until_seq"), 0))' 'if (seq > intOr(permit.kv.get("permit|until_seq"), 0))' "expiry off by one"
plant 'if (revoked.contains(s.keyId) || (permit != null && revoked.contains(permit.keyId)))' 'if (revoked.contains(s.keyId))' "revoked root behind a permit ignored"
echo "all checks passed"
