# bootstrap

Turns an empty Multica workspace into a running spec-crew squad.

```bash
./bootstrap/bootstrap.sh --dry-run    # print every call, change nothing
./bootstrap/bootstrap.sh              # do it
```

Run it from the repository root. It is safe to re-run: existing skills are
skipped, and existing agents and squads are updated rather than duplicated.

## What it creates

| Phase | Creates | CLI-able |
|---|---|---|
| `preflight` | — verifies CLI, auth, workspace, runtime; registers repos | yes |
| `skills` | 12 Matt skills + 2 workspace skills | yes |
| `statuses` | — verifies and maps; cannot create | **no** |
| `agents` | Coordinator, Builder, Reviewer, Inspector + skill bindings | yes |
| `squad` | the squad, its leader instructions, its members | yes |
| `autopilot` | Inspector's scheduled inspection (opt-in) | yes |
| `verify` | — reports what ended up bound | yes |

Run one phase with `--only <phase>`.

## Answering "what else, aside from skills and agents?"

Six things, and only three of them have a CLI.

1. **The squad.** Four agents with no leader are inert. `squad create` has no
   `--instructions` flag, so it is a create-then-update, and squad instructions
   reach the **leader only** — members never see them.
2. **Skill bindings.** `agent create` does *not* bind skills, even though the
   HTTP body accepts `skill_ids`. Separate call, separate failure mode.
3. **Repositories.** `multica repo add <url>`. Set `REPOS=` to register them.
   This is only a checkout registry — it does not wire up PR linking.
4. **Custom statuses.** No CLI at all. See below.
5. **GitHub integration.** No CLI. Without it, PRs never link back to issues
   and `Closes ILLO-N` does nothing on merge.
6. **`conversation_starters`.** No CLI flag on create or update; only
   `agent copy` carries an existing value forward. Web UI or the API.

An **autopilot** is optional — needed only if you want Inspector's scheduled
inspections. It is off by default because a schedule starts recurring paid
runs. `CREATE_AUTOPILOT=1` turns it on.

You do **not** need labels or custom properties. Planning state lives in the
status and nowhere else.

## Statuses: the part that needs you

A status key is 1-32 characters of lowercase letters, digits, or underscore.
Hyphens are rejected by the server.

The kit expects four custom statuses:

| Key | Category |
|---|---|
| `prd_draft` | `backlog` |
| `ready_for_slicing` | `backlog` |
| `needs_triage` | `backlog` |
| `needs_clarification` | `blocked` |

**The category is what matters, not the name.** Agents branch on
`status_category`. A backlog-category status parks work; a todo-category status
starts it. A status created under the wrong category silently breaks the
pipeline in a way nothing will warn you about at runtime.

The CLI cannot create statuses, so bootstrap discovers what exists instead. It
reads the catalog out of the server's own rejection message — `issue status`
documents that an unknown value errors with the full list — then reports what is
missing and the exact category each needs.

### If your workspace already uses different keys

You do not have to rename anything. Point the kit at your keys:

```bash
STATUS_MAP="needs_clarification=needs_clarification_3" ./bootstrap/bootstrap.sh --dry-run
```

Bootstrap rewrites the instruction payloads before creating the agents, so they
write keys your server actually accepts. It also *suggests* a `STATUS_MAP` when
it spots similar unclaimed keys — but it never applies one on its own, because
guessing a category wrong is exactly the failure it cannot detect.

## Configuration

Everything is an environment variable; nothing needs the script edited.

| Variable | Default | |
|---|---|---|
| `RUNTIME_ID` | auto-detected | Required if the workspace has more than one runtime |
| `SQUAD_NAME` | `spec-crew` | |
| `STATUS_MAP` | — | `canonical=actual,...` |
| `REPOS` | — | Space-separated repo URLs to register |
| `MODEL_COORDINATOR` | `claude-opus-5` | reasoning-tier model |
| `MODEL_BUILDER` | `claude-opus-5` | coding-tier model |
| `MODEL_REVIEWER` | `claude-opus-5` | reasoning-tier model |
| `MODEL_INSPECTOR` | `claude-haiku-4-5` | cheap tier; 200K context, no effort support |
| `THINKING_COORDINATOR` | `xhigh` | effort, `low`–`max` |
| `THINKING_BUILDER` | `xhigh` | effort, `low`–`max` |
| `THINKING_REVIEWER` | `high` | effort, `low`–`max` |
| `THINKING_INSPECTOR` | `low` | effort; Haiku 4.5 may reject it entirely |
| `CREATE_AUTOPILOT` | `0` | `1` creates the scheduled inspection |
| `AUTOPILOT_CRON` | `0 9 * * 1` | |

Builder runs at `xhigh` because that is the recommended effort for coding and
agentic work, and because a weak implementation costs a Reviewer round plus a
review-fix round. Higher effort does pull the model toward unrequested tidying
and refactoring. If that shows up in Builder PRs, sharpen the scope boundary in
[`agents/builder.md`](../agents/builder.md) — "structural decisions beyond the
issue scope are blockers" — rather than dropping the effort back down. The
scope contract is the right lever; effort is not.

Which skills exist and which agent binds them is data, not code:
[`skills.txt`](skills.txt) and [`agents.txt`](agents.txt).

## Notes

- `lib/common.sh` targets bash 3.2, which is what macOS ships. No associative
  arrays, no `${var,,}`.
- `.bootstrap-state` records created ids so re-runs update instead of
  duplicating. Delete it to force a clean create.
- Matt's skills are imported from **his** repo, not from `matt-skills/` here.
  That mirror is for reading and diffing; the runtime copy should track upstream
  so `multica skill refresh` works.
