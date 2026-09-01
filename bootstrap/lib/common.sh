# Shared helpers for the spec-crew bootstrap. Sourced, never executed.
# Targets bash 3.2 (what macOS ships) — no associative arrays, no ${x,,}.

set -euo pipefail

: "${DRY_RUN:=0}"

_c() { [[ -t 2 ]] && printf '\033[%sm' "$1" >&2 || true; }
info() { _c 36; printf '==> ' >&2; _c 0; printf '%s\n' "$*" >&2; }
step() { _c 35; printf '\n### %s\n' "$*" >&2; _c 0; }
warn() { _c 33; printf 'warn: ' >&2; _c 0; printf '%s\n' "$*" >&2; }
ok()   { _c 32; printf '  ok  ' >&2; _c 0; printf '%s\n' "$*" >&2; }
skip() { _c 90; printf '  --  %s\n' "$*" >&2; _c 0; }
die()  { _c 31; printf 'error: ' >&2; _c 0; printf '%s\n' "$*" >&2; exit 1; }

# Print a command in dry-run, execute it otherwise. Never writes to stdout on
# the dry-run path — callers capture ids with $(...) and log lines would
# corrupt them.
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    _c 90; printf '  $ %s\n' "$(printf '%q ' "$@")" >&2; _c 0
    return 0
  fi
  "$@"
}

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

json_get() { python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[sys.argv[1]])' "$1"; }

# Read a JSON list-or-{key:list} envelope and print "id<TAB>name" per row.
json_rows() {
  python3 -c '
import sys, json
d = json.load(sys.stdin)
rows = d if isinstance(d, list) else d.get(sys.argv[1], [])
for r in rows:
    print("%s\t%s" % (r.get("id",""), r.get("name","")))
' "$1"
}

# Extract the literal --instructions payload from an agents/*.md file: the one
# ````md fenced block following "## Instructions". See agents/TEMPLATE.md.
extract_instructions() {
  [[ -f "$1" ]] || die "no such file: $1"
  python3 - "$1" <<'PY'
import io, re, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
_, sep, tail = src.partition("## Instructions\n")
if not sep:
    sys.exit("%s: no '## Instructions' heading" % sys.argv[1])
m = re.match(r"\n````md\n(.*)\n````\s*$", tail, re.S)
if not m:
    sys.exit("%s: '## Instructions' is not exactly one ````md fenced block "
             "spanning the rest of the file" % sys.argv[1])
body = m.group(1)
if not body.strip():
    sys.exit("%s: instruction block is empty" % sys.argv[1])
sys.stdout.write(body)
PY
}
