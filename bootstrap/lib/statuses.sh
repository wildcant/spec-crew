# Status discovery and mapping. Sourced by bootstrap.sh.
#
# There is no `multica status` command — custom statuses are created by a human
# in Settings > Issue Statuses. What this module CAN do is discover which keys
# exist, tell you exactly what is missing, and reconcile a workspace whose keys
# differ from the ones this kit ships.

# The four the kit expects, and the category each MUST have.
# Category is the contract: agents branch on status_category, not on the name.
CANONICAL_STATUSES="prd_draft:backlog ready_for_slicing:backlog needs_triage:backlog needs_clarification:blocked"

# Discover the workspace's status catalog.
#
# The CLI has no list command, but `issue status` documents that "an unknown
# value errors with the full list", so we ask for a key that cannot exist and
# read the catalog out of the rejection. Nothing is mutated: the status is
# validated before any write.
discover_status_keys() {
  local any_issue="$1" out
  out="$(multica issue status "$any_issue" zzz_nonexistent_probe --no-start 2>&1 || true)"
  case "$out" in
    *"valid values:"*) ;;
    *) die "could not read the status catalog. multica said: $out" ;;
  esac
  printf '%s\n' "$out" \
    | sed 's/.*valid values: //' \
    | tr ',' '\n' \
    | sed -e 's/(.*)//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$'
}

# Categories for statuses that some issue currently sits in. Free and
# non-mutating, but only covers statuses actually in use — an unused custom
# status is invisible here, which is why we report rather than assume.
observed_categories() {
  multica issue list --output json 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin)
rows = d if isinstance(d, list) else d.get("issues", [])
seen = {}
for r in rows:
    if r.get("status") and r.get("status_category"):
        seen[r["status"]] = r["status_category"]
for k in sorted(seen):
    print("%s\t%s" % (k, seen[k]))
' || true
}

# Resolve each canonical key to a key that exists in this workspace.
# Writes "canonical<TAB>resolved" lines to stdout; diagnostics to stderr.
# Honours STATUS_MAP="canonical=actual,canonical=actual".
resolve_statuses() {
  local available="$1" canonical actual entry mapped
  for entry in $CANONICAL_STATUSES; do
    canonical="${entry%%:*}"
    mapped=""

    # 1. explicit override wins
    if [[ -n "${STATUS_MAP:-}" ]]; then
      mapped="$(printf '%s' "$STATUS_MAP" | tr ',' '\n' \
                | sed -n "s/^[[:space:]]*${canonical}=//p" | head -1)"
    fi

    # 2. otherwise the canonical key itself, if the workspace has it
    if [[ -z "$mapped" ]] && printf '%s\n' "$available" | grep -qx "$canonical"; then
      mapped="$canonical"
    fi

    if [[ -n "$mapped" ]]; then
      if ! printf '%s\n' "$available" | grep -qx "$mapped"; then
        die "STATUS_MAP sends $canonical -> $mapped, but $mapped is not a status in this workspace"
      fi
      printf '%s\t%s\n' "$canonical" "$mapped"
    else
      printf '%s\t\n' "$canonical"
    fi
  done
}

# Suggest a mapping for missing canonical keys from unclaimed custom keys,
# scored on shared word stems. Suggestions are printed for a human to confirm —
# never applied automatically. Guessing a category wrong silently breaks the
# pipeline, so this stops at a recommendation.
suggest_status_map() {
  python3 - "$1" "$2" <<'PY'
import sys
available = [k for k in sys.argv[1].split() if k]
missing   = [k for k in sys.argv[2].split() if k]
builtin = {"backlog","todo","in_progress","in_review","done","blocked","cancelled"}
pool = [k for k in available if k not in builtin]
def words(k): return set(w for w in k.split("_") if len(w) > 2)
pairs = []
for m in missing:
    best, score = None, 0
    for c in pool:
        s = len(words(m) & words(c))
        if s > score:
            best, score = c, s
    if best:
        pairs.append("%s=%s" % (m, best))
        pool.remove(best)
if pairs:
    print("STATUS_MAP=\"%s\"" % ",".join(pairs))
PY
}

# Rewrite canonical status keys to this workspace's keys inside an instruction
# payload, so agents write keys the server will actually accept.
#
# Takes the payload as $2, not on stdin: the python program arrives via heredoc,
# which occupies stdin, so a piped payload would be swallowed and come back empty.
apply_status_map() {
  python3 - "$1" "$2" <<'PY'
import sys, re
text = sys.argv[2]
pairs = [p for p in sys.argv[1].split("\n") if "\t" in p]
subs = {}
for p in pairs:
    canonical, actual = p.split("\t", 1)
    if actual and actual != canonical:
        subs[canonical] = actual
if subs:
    pat = re.compile(r"\b(%s)\b" % "|".join(re.escape(k) for k in subs))
    text = pat.sub(lambda m: subs[m.group(1)], text)
sys.stdout.write(text)
PY
}
