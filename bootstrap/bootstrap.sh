#!/usr/bin/env bash
#
# Bootstrap the spec-crew workflow into a Multica workspace.
#
#   ./bootstrap/bootstrap.sh --dry-run     print every call, change nothing
#   ./bootstrap/bootstrap.sh               do it
#   ./bootstrap/bootstrap.sh --only skills run one phase
#
# Phases: preflight, skills, statuses, agents, squad, autopilot, verify
#
# Safe to re-run. Existing skills are skipped, and existing agents/squads are
# UPDATED rather than duplicated.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

. "$HERE/lib/common.sh"
. "$HERE/lib/statuses.sh"

# ---------------------------------------------------------------- config ----

RUNTIME_ID="${RUNTIME_ID:-}"
SQUAD_NAME="${SQUAD_NAME:-spec-crew}"

MODEL_COORDINATOR="${MODEL_COORDINATOR:-claude-opus-5}"
MODEL_BUILDER="${MODEL_BUILDER:-claude-opus-5}"
MODEL_REVIEWER="${MODEL_REVIEWER:-claude-opus-5}"
MODEL_INSPECTOR="${MODEL_INSPECTOR:-claude-haiku-4-5}"

THINKING_COORDINATOR="${THINKING_COORDINATOR:-xhigh}"
THINKING_BUILDER="${THINKING_BUILDER:-xhigh}"
THINKING_REVIEWER="${THINKING_REVIEWER:-high}"
THINKING_INSPECTOR="${THINKING_INSPECTOR:-low}"

# Repositories to register, space separated. Empty = skip.
REPOS="${REPOS:-}"

# Create the Inspector's scheduled inspection autopilot. Off by default: it
# starts a recurring paid run, which should be an opt-in.
CREATE_AUTOPILOT="${CREATE_AUTOPILOT:-0}"
AUTOPILOT_CRON="${AUTOPILOT_CRON:-0 9 * * 1}"
AUTOPILOT_TZ="${AUTOPILOT_TZ:-UTC}"

ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --only)    ONLY="${2:-}"; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         die "unknown argument: $1" ;;
  esac
  shift
done

phase() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

STATE="$HERE/.bootstrap-state"   # name<TAB>id, so re-runs update instead of duplicating
touch "$STATE" 2>/dev/null || true
remember() { printf '%s\t%s\n' "$1" "$2" >> "$STATE"; }
recall()   { [[ -f "$STATE" ]] && awk -F'\t' -v k="$1" '$1==k{v=$2} END{print v}' "$STATE" || true; }

# ------------------------------------------------------------- preflight ----

if phase preflight; then
  step "Preflight"
  need multica; need python3
  ok "multica $(multica version 2>/dev/null | head -1)"

  [[ -d agents && -d skills ]] || die "run this from a spec-crew checkout (no ./agents and ./skills here)"

  multica workspace get --output json >/dev/null 2>&1 \
    || die "not authenticated, or no default workspace. Run: multica login"
  WS_NAME="$(multica workspace get --output json | json_get name)"
  ok "workspace: $WS_NAME"

  if [[ -z "$RUNTIME_ID" ]]; then
    RUNTIME_ID="$(multica runtime list --output json | python3 -c '
import sys, json
rts = json.load(sys.stdin)
pool = [r for r in rts if r.get("status") == "online"] or rts
if not pool:
    sys.exit("no runtimes in this workspace. Start the daemon: multica daemon start")
if len(pool) > 1:
    lines = ["  %s  %s  (%s)" % (r["id"], r.get("name",""), r.get("status")) for r in pool]
    sys.exit("%d runtimes found — choose one and re-run with RUNTIME_ID=<id>:\n%s"
             % (len(pool), "\n".join(lines)))
print(pool[0]["id"])
')" || die "$(cat)"
  fi
  ok "runtime: $RUNTIME_ID"
  remember RUNTIME_ID "$RUNTIME_ID"
fi
[[ -n "$RUNTIME_ID" ]] || RUNTIME_ID="$(recall RUNTIME_ID)"

# ---------------------------------------------------------------- repos -----

if phase preflight && [[ -n "$REPOS" ]]; then
  step "Repositories"
  for r in $REPOS; do
    if multica repo list --output json | grep -qF "\"$r\""; then
      skip "already registered: $r"
    else
      info "registering $r"
      run multica repo add "$r" >/dev/null
    fi
  done
fi

# --------------------------------------------------------------- skills -----

if phase skills; then
  step "Skills"
  EXISTING="$(multica skill list --output json | json_rows skills | cut -f2)"
  while read -r name url; do
    case "$name" in ''|\#*) continue ;; esac
    if printf '%s\n' "$EXISTING" | grep -qx "$name"; then
      skip "already imported: $name"
      continue
    fi
    info "importing $name"
    run multica skill import --url "$url" --on-conflict skip >/dev/null \
      || warn "import failed for $name — check the URL in bootstrap/skills.txt"
  done < <(sed 's/#.*//' "$HERE/skills.txt")
fi

# ------------------------------------------------------------- statuses -----

STATUS_PAIRS=""
if phase statuses || phase agents; then
  step "Statuses"
  ANY_ISSUE="$(multica issue list --output json | python3 -c '
import sys, json
d = json.load(sys.stdin); rows = d if isinstance(d, list) else d.get("issues", [])
print(rows[0]["id"] if rows else "")')"

  if [[ -z "$ANY_ISSUE" ]]; then
    warn "no issue exists yet, so the status catalog cannot be probed."
    warn "create any issue, then re-run: ./bootstrap/bootstrap.sh --only statuses"
  else
    AVAILABLE="$(discover_status_keys "$ANY_ISSUE")"
    ok "catalog: $(printf '%s' "$AVAILABLE" | tr '\n' ' ')"

    STATUS_PAIRS="$(resolve_statuses "$AVAILABLE")"
    MISSING=""
    while IFS="$(printf '\t')" read -r canonical actual; do
      [[ -z "$canonical" ]] && continue
      if [[ -n "$actual" ]]; then
        if [[ "$actual" == "$canonical" ]]; then ok "$canonical"
        else ok "$canonical -> $actual (mapped)"; fi
      else
        MISSING="$MISSING $canonical"
      fi
    done <<< "$STATUS_PAIRS"

    if [[ -n "$MISSING" ]]; then
      warn "missing statuses:$MISSING"
      warn ""
      warn "Statuses cannot be created from the CLI. In Settings > Issue Statuses, add:"
      for entry in $CANONICAL_STATUSES; do
        c="${entry%%:*}"; cat="${entry##*:}"
        case " $MISSING " in *" $c "*) warn "    key: $c    category: $cat" ;; esac
      done
      warn ""
      warn "The CATEGORY is what the agents act on — a backlog status parks work,"
      warn "a todo status starts it. A wrong category silently breaks the pipeline."
      SUGGESTION="$(suggest_status_map "$(printf '%s' "$AVAILABLE" | tr '\n' ' ')" "$MISSING")"
      if [[ -n "$SUGGESTION" ]]; then
        warn ""
        warn "This workspace already has similar keys. If they are the same thing"
        warn "with the right categories, re-run with:"
        warn "    $SUGGESTION"
      fi
    fi
  fi

  # Report categories we can actually observe. An unused status is invisible here.
  OBSERVED="$(observed_categories)"
  while IFS="$(printf '\t')" read -r s c; do
    [[ -z "$s" ]] && continue
    for entry in $CANONICAL_STATUSES; do
      want_key="${entry%%:*}"; want_cat="${entry##*:}"
      while IFS="$(printf '\t')" read -r canonical actual; do
        if [[ "$canonical" == "$want_key" && "$actual" == "$s" && "$c" != "$want_cat" ]]; then
          warn "$s has category '$c' but the workflow needs '$want_cat' — fix it in Settings"
        fi
      done <<< "$STATUS_PAIRS"
    done
  done <<< "$OBSERVED"
fi

# --------------------------------------------------------------- agents -----

if phase agents; then
  step "Agents"
  SKILL_ROWS="$(multica skill list --output json | json_rows skills)"
  AGENT_ROWS="$(multica agent list --output json | json_rows agents)"

  skill_ids_for() {
    local want ids="" id
    for want in "$@"; do
      id="$(printf '%s\n' "$SKILL_ROWS" | awk -F'\t' -v n="$want" '$2==n{print $1; exit}')"
      if [[ -z "$id" ]]; then warn "  skill not in workspace, not bound: $want"
      else ids="${ids:+$ids,}$id"; fi
    done
    printf '%s' "$ids"
  }

  while read -r name file model_var thinking_var version rest; do
    case "$name" in ''|\#*) continue ;; esac
    model="$(eval printf '%s' "\"\${$model_var}\"")"
    thinking="$(eval printf '%s' "\"\${$thinking_var}\"")"

    payload="$(extract_instructions "$file")"
    if [[ -n "$STATUS_PAIRS" ]]; then
      payload="$(apply_status_map "$STATUS_PAIRS" "$payload")"
    fi

    existing="$(printf '%s\n' "$AGENT_ROWS" | awk -F'\t' -v n="$name" '$2==n{print $1; exit}')"
    if [[ -n "$existing" ]]; then
      info "updating $name ($existing)"
      run multica agent update "$existing" \
        --instructions "$payload" \
        --description "spec-crew $name. Instruction version: $version" >/dev/null
      agent_id="$existing"
    else
      info "creating $name (${#payload} chars of instructions, model $model)"
      if [[ "$DRY_RUN" == "1" ]]; then
        agent_id="dry-run-$name"
        run multica agent create --name "$name" --runtime-id "$RUNTIME_ID" \
          --instructions "<${#payload} chars from $file>" \
          --description "spec-crew $name. Instruction version: $version" \
          --model "$model" --thinking-level "$thinking" \
          --max-concurrent-tasks 1 --permission-mode public_to --public-to-workspace
      else
        agent_id="$(multica agent create --name "$name" --runtime-id "$RUNTIME_ID" \
          --instructions "$payload" \
          --description "spec-crew $name. Instruction version: $version" \
          --model "$model" --thinking-level "$thinking" \
          --max-concurrent-tasks 1 --permission-mode public_to --public-to-workspace \
          --output json | json_get id)"
      fi
    fi
    remember "agent:$name" "$agent_id"

    ids="$(skill_ids_for $rest)"
    if [[ -n "$ids" ]]; then
      info "  binding $(printf '%s' "$rest" | wc -w | tr -d ' ') skills"
      run multica agent skills add "$agent_id" --skill-ids "$ids" >/dev/null
    else
      warn "  no skills bound to $name — import them, then: ./bootstrap/bootstrap.sh --only agents"
    fi
  done < <(sed 's/^#.*//' "$HERE/agents.txt")
fi

# ---------------------------------------------------------------- squad -----

if phase squad; then
  step "Squad"
  COORDINATOR_ID="$(recall 'agent:Coordinator')"
  [[ -n "$COORDINATOR_ID" ]] || die "no Coordinator id recorded — run the agents phase first"

  SQUAD_ID="$(multica squad list --output json 2>/dev/null | json_rows squads \
              | awk -F'\t' -v n="$SQUAD_NAME" '$2==n{print $1; exit}')"
  if [[ -n "$SQUAD_ID" ]]; then
    skip "squad exists: $SQUAD_NAME ($SQUAD_ID)"
  else
    info "creating squad $SQUAD_NAME"
    if [[ "$DRY_RUN" == "1" ]]; then
      SQUAD_ID="dry-run-squad"
      run multica squad create --name "$SQUAD_NAME" --leader "$COORDINATOR_ID" --description "..."
    else
      SQUAD_ID="$(multica squad create --name "$SQUAD_NAME" --leader "$COORDINATOR_ID" \
        --description "Coordinator plans and dispatches; Builder implements; Reviewer reviews; Inspector inspects." \
        --output json | json_get id)"
    fi
  fi
  remember SQUAD_ID "$SQUAD_ID"

  # squad.md is the whole leader briefing — it has no ## Instructions fence,
  # and Multica injects it into the LEADER ONLY. Members never see it.
  info "setting leader instructions from agents/squad.md"
  if [[ "$DRY_RUN" == "1" ]]; then
    run multica squad update "$SQUAD_ID" --instructions "<$(wc -c < agents/squad.md | tr -d ' ') chars from agents/squad.md>"
  else
    multica squad update "$SQUAD_ID" --instructions "$(cat agents/squad.md)" >/dev/null
  fi

  for m in Builder Reviewer Inspector; do
    mid="$(recall "agent:$m")"
    [[ -n "$mid" ]] || { warn "no id for $m, skipping"; continue; }
    if multica squad get "$SQUAD_ID" --output json 2>/dev/null | grep -qF "$mid"; then
      skip "$m already a member"
    else
      info "adding $m"
      run multica squad member add "$SQUAD_ID" --member-id "$mid" --type agent --role member >/dev/null
    fi
  done
fi

# ------------------------------------------------------------ autopilot -----

if phase autopilot && [[ "$CREATE_AUTOPILOT" == "1" ]]; then
  step "Autopilot"
  INSPECTOR_ID="$(recall 'agent:Inspector')"
  [[ -n "$INSPECTOR_ID" ]] || die "no Inspector id recorded — run the agents phase first"
  info "creating scheduled inspection autopilot ($AUTOPILOT_CRON $AUTOPILOT_TZ)"
  if [[ "$DRY_RUN" == "1" ]]; then
    AP_ID="dry-run-autopilot"
    run multica autopilot create --title "Weekly todo-scan" --agent "$INSPECTOR_ID" --mode create_issue
  else
    AP_ID="$(multica autopilot create \
      --title "Weekly todo-scan" \
      --agent "$INSPECTOR_ID" \
      --mode create_issue \
      --issue-title-template '[inspection][todo-scan] {{date}}' \
      --description 'inspection_type: todo-scan. Scan the configured scope for TODO/FIXME/XXX markers and report them grouped by repo and file. Read-only: recommend only, never edit.' \
      --output json | json_get id)"
  fi
  run multica autopilot trigger-add "$AP_ID" --kind schedule --cron "$AUTOPILOT_CRON" \
    --timezone "$AUTOPILOT_TZ" --label "weekly" >/dev/null
elif phase autopilot; then
  step "Autopilot"
  skip "CREATE_AUTOPILOT=0 — a schedule starts recurring paid runs, so it is opt-in"
fi

# --------------------------------------------------------------- verify -----

if phase verify; then
  step "Verify"
  for n in Coordinator Builder Reviewer Inspector; do
    id="$(recall "agent:$n")"
    if [[ -z "$id" || "$DRY_RUN" == "1" ]]; then skip "$n"; continue; fi
    bound="$(multica agent skills list "$id" --output json 2>/dev/null | json_rows skills | wc -l | tr -d ' ')"
    ok "$n  $id  ($bound skills bound)"
  done
  sid="$(recall SQUAD_ID)"
  [[ -n "$sid" ]] && ok "squad  $sid"
fi

# ----------------------------------------------------------------- next -----

step "Remaining manual steps"
cat >&2 <<'EOF'
These have no CLI surface. Nothing above can do them for you.

  1. Custom statuses — Settings > Issue Statuses. Categories matter more than
     names; the agents branch on status_category.
  2. GitHub integration — connect GitHub and install it on the repo, or PRs
     will never link back to issues and "Closes ILLO-N" will do nothing.
  3. conversation_starters — no CLI flag on create or update. Web UI only.

Then assign a parent issue to the squad. Squads do not fan out: the assignment
enqueues the Coordinator, which creates and assigns the child issues itself.
EOF
