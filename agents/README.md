# Agent Designs

Four agents, designed around the workflow in this repository.

## Agents

- [`Planner / Coordinator`](./planner-coordinator.md): the only dispatcher. Clarification, PRD, issue slicing, triage, dispatch.
- [`Builder`](./builder.md): implements issues in `todo`. Small steps, tests first.
- [`Reviewer`](./reviewer.md): reviews implementation results. Finds bugs, regressions, missing tests, risk.
- [`Inspector`](./inspector.md): general-purpose inspection agent. Routes skills on `inspection_type`; ships one minimal built-in example type, `todo-scan` (read-only scan for `TODO`/`FIXME`/`XXX`). `scope` may be a Multica project or a single repo. Supports self-service bootstrap: the user describes a new inspection need, and Inspector drafts the skill, binds it to itself, registers the type, and — after confirmation — creates the autopilot. Types such as `context` are all created this way.

## Final Skills

The skills each agent design binds. Matt Skills and Workspace Skills are listed separately; at deploy time the bindings recorded in Multica are authoritative.

- `Planner / Coordinator`: Matt `grilling`, `to-spec`, `to-tickets`, `triage`; Workspace `branch-pr-safety`
- `Builder`: Matt `codebase-design`, `diagnosing-bugs`, `resolving-merge-conflicts`, `tdd`; Workspace `branch-pr-safety`
- `Reviewer`: Matt `code-review`, `tdd`; Workspace `branch-pr-safety`
- `Inspector`: Matt `grill-with-docs`, `handoff`, `writing-for-agents`

## Dispatch Rule

Only the `Planner / Coordinator` may create child issues, assign agents, or move cross-agent state.

Members never dispatch each other:

- `Builder` moves the issue to `in_review` when done and hands it back to the `Planner / Coordinator`.
- `Reviewer` writes `review_result` (`approved` / `changes-requested` / `needs-info`) into its result packet, never as a status. Either outcome lands the review issue at `in_review` and hands it back to the `Planner / Coordinator`; Reviewer never advances acceptance or merges.
- `Inspector` produces reports and proposals only by default. The `context` type may write approved context files on a re-trigger, and only after explicit human confirmation. Read-only types stay read-only throughout. Every dangerous action requires human confirmation.

Builder implementation work on the same repo is serial by default. Parallel runs are allowed only with confirmed isolated worktrees.

## Notification Rule

On the chat surface where the request originated, the user only needs to @ the `Planner / Coordinator`. When dispatching, the `Planner / Coordinator` passes the original requester, the originating group/thread, and the parent request link to `Builder` as internal notification context.

On completion or blocker, `Builder` may notify the original requester once in the originating group/thread. The notification carries only the implementation result, the Builder PR link, the build/verification outcome, and any risk or blocker. `Builder` never @-mentions `Reviewer`, never dispatches another agent, and never advances the review loop.

`Builder` handing back to the `Planner / Coordinator` is a state handoff, not a dispatch. Prefer assigning the issue back; if assignment is unavailable, leave one @Coordinator completion or blocker comment on the issue. The user should never have to ask for review manually.

`Reviewer` does not reassign issues beyond handing back. On completion it leaves one user-facing @Coordinator review summary. The `Planner / Coordinator` owns the review-fix cycle, the Builder PR merge, user acceptance, and the Final PR.

`Inspector` writes one Inspection result packet on completion, then hands the inspection issue back to the `Planner / Coordinator`. Implementation recommendations must become their own issue and pass the ready-for-work gate again before reaching `todo`.

Authority boundaries:

- Dispatch: `Planner / Coordinator` only.
- Execution: `Builder`.
- Completion/blocker notification: `Builder` may notify the original requester or group.
- Triggering a re-review: `Planner / Coordinator` only.

## Review Loop Budget

Only the `Planner / Coordinator` may trigger `Reviewer`. One review run is one review round; the P0/P1/P2 findings inside it are not counted individually. `Builder` may fix findings from the same round in several batches, but hands back to the Coordinator once, after every required finding is done. A follow-up review verifies only whether the previous round's findings were resolved and whether the fix introduced an obvious new P0/P1 regression — it does not re-review the fix as if it were unrelated new work. At most one automatic review-fix cycle per issue; on a second `changes-requested`, stop automating, move the issue to `needs_clarification`, and state the human decision needed.

## Human Gates

- PRD confirmation.
- Authorization to open the Final PR.
- Final PR review and merge, done on GitHub.
- `done` is written by a human. Agents land at `in_review`.

The Builder PR (`work_branch -> source_branch`) is an internal integration step. After Reviewer approval the `Planner / Coordinator` merges it where policy allows, and otherwise asks a human to merge and waits. Once the merge is done and the reviewed head is verified to be in `source_branch`, obtain human authorization to open the Final PR. The Final PR is the human review gate: agents open it, move the parent to `in_review`, and stop.

## Status Model

Planning state lives in the issue status and nowhere else. Statuses are
exclusive; labels are a set. An issue that is simultaneously `prd_draft` and
`needs_triage` is a bug we would otherwise have to prevent, so planning state
never uses labels.

Issue JSON exposes `status`, `status_category`, and `status_name` separately.
**Every agent branches on `status_category`, never on the status name.** A
custom status inherits its category's platform behaviour in full: the category
is the contract, the name is for humans and differs per workspace.

Four custom statuses, created once in Settings → Issue Statuses, plus the
built-ins:

| Status | Category | Meaning |
|---|---|---|
| `needs_clarification` | `blocked` | Coordinator is waiting on a human answer |
| `blocked` | `blocked` | Waiting on something that is not a question |
| `prd_draft` | `backlog` | Drafting the spec |
| `ready_for_slicing` | `backlog` | Spec done, not yet sliced |
| `needs_triage` | `backlog` | Sliced, not yet prioritised |
| `todo` | `todo` | Executable — native `todo` *is* `ready-for-agent` |
| `in_progress` | `in_progress` | Work underway |
| `in_review` | `in_review` | Delivered, awaiting human acceptance |
| `done` | `done` | Human only |
| `cancelled` | `cancelled` | Dropped |

A status **key** is 1-32 characters of lowercase letters, digits, or underscore
— hyphens are rejected by the server. The keys above are the canonical ones this
kit expects; if your workspace already uses different keys for the same
categories, `bootstrap/` rewrites these instructions to match rather than
requiring you to rename anything.

Why this works: assigning an issue that sits in a backlog-category status does
not start a run, and moving it out of backlog wakes the assignee. So the parked
statuses are exactly the planning ones, and reaching `todo` is the moment work
becomes executable. The platform enforces the pipeline; no agent has to.

```text
needs_clarification (blocked, any point)
prd_draft -> ready_for_slicing -> needs_triage   (backlog: parked)
-> todo          (executable; assignment now starts the agent)
-> in_progress
-> in_review     (agents stop here)
-> done          (human)
```

There is no post-implementation status vocabulary. The upstream
`ready-for-review` / `review-approved` / `ready-for-acceptance` /
`ready-for-human-merge` chain is deleted, not migrated: those handoffs are now
child-issue ownership plus comment packets. `review_result` is a field in the
Reviewer's packet, not a status.

## Squad Mechanics

The Coordinator is the squad leader. The platform does not do these for it:

- **Squads do not fan out.** Assigning an issue to the squad enqueues the leader
  only. The Coordinator creates child issues and assigns each to a named member.
- **Members never assign to each other.** Every handoff returns to the Coordinator.
- **Dependency ordering uses `--stage N`.** The leader is woken only when every
  sub-issue in a stage finishes.
- **Review is its own child issue assigned to the Reviewer** — a separate run
  with fresh context, a stronger isolation boundary than a sub-agent, and it
  removes author bias.
- **Parent status authority belongs to the leader**, and only while the issue is
  assigned to this squad. The server does not flip the parent when children
  finish.
- **`done` stays human.** Agents land work at `in_review`; the GitHub review is
  the gate.
- **Execution is serial.** Keep `max_concurrent_tasks: 1` on every agent. Where
  a plan needs genuine parallelism, prefer sub-agent fan-out inside one ticket
  over concurrent tickets, so the work stays on one branch.

## Branch And PR Safety

Everyone uses [`branch-pr-safety`](../skills/branch-pr-safety/SKILL.md). Branch and PR fields are the agents' internal control plane, not default user-facing reporting. By default the user sees the implementation result, the PR link, the verification outcome, risks, and any blocker needing a human decision.

Before dispatching, the `Planner / Coordinator` reads the child issue's visible key, then writes the goal, acceptance criteria, verification, and complete Delivery Context into the child issue: `repo`, `base_branch`, `source_branch`, `source_branch_status`, `issue_key`, `work_branch`, `builder_pr_target`, `final_pr_target`. This is the minimum branch-safety context kept on the issue because there is no private dispatch channel; the public issue carries no agent packets, SHAs, commands, raw test output, or routing fields.

On completion, Builder reports only the change, the Builder PR, the build/test conclusion, the risks, and `source_branch`. The Coordinator gets refs, diff, changed files, check results, and branch state from Git/PR.

When creating the review issue, the Coordinator supplies the public issue and the Builder PR link. Reviewer resolves the immutable diff, tests, and branch state from Git/PR.

Reviewer publishes a public Review summary: result, Builder PR, blocking findings, non-blocking follow-ups, test gaps, residual risks. Every finding needs a stable id; review refs and branch state stay in Git/PR.

Inspector publishes an Inspection result packet: type, scope, result, action required, human approval, approved scope, findings, evidence, actions, follow-up refs, remaining decisions.

`work_branch` must use the visible issue key: `agent/<issue_key>-<short-slug>`, for example `agent/PROJ-338-deep-link`. Never a project id, a UUID, or an internal task id.

`repo` may be a Multica project name, a repository name, or a remote URL. If the workspace or issue context exposes exactly one project/repo, the `Planner / Coordinator` infers `repo` directly and does not ask for a repo address.

New requirements default to `source_branch_status: create_if_missing`. A missing remote `source_branch` is therefore the expected state, and `Builder` creates it from the latest `base_branch` and pushes it. Use `source_branch_status: must_exist` only when the user names an existing integration, feature, or hotfix branch.

## Build Check

`Builder` runs the project build for UI changes before moving the issue to `in_review`; a failing build means the delivery is not done. Interactive and visual acceptance happens on the target environment after the Final PR is merged.

Where an existing test seam is available, Builder adds focused coverage and Reviewer reviews for missing tests. Where no viable seam exists, the Coordinator records the evidence and the fallback verification on the issue, Builder does not stand up a new test framework, and Reviewer treats the test gap as a risk rather than an automatic blocker.

## Shared Communication Instruction

```md
Communication:

- Use terse English.
- No filler, pleasantries, hedging, repetition.
- Pattern: [thing] [action] [reason]. [next step].
- Keep code symbols, API names, errors, commands exact.
- Use normal, clear prose for security warnings, destructive actions, and order-sensitive steps.
```

## Skill Precedence

Agent instructions and issue/PR context override loaded Skill workflows. Skills provide methods and templates only. They do not widen an agent's permissions, skip a human gate, or change dispatcher ownership.

- Coordinator may use `to-spec` / `to-tickets` / `triage` for in-scope read-only source exploration. It must not check out code, edit, install dependencies, run project code/build/tests, move an issue to `todo` automatically, or invoke `/implement`.
- Builder treats the issue's verification path as already confirmed. No skill may trigger review or open the Final PR on its own.
- Reviewer always reviews the immutable commit refs resolved from the Builder PR. No skill may ask the user which findings to fix, apply fixes, or trigger Builder directly.
- Inspector performs only the actions the current `inspection_type` explicitly authorizes.

## Deployment Sync Rule

`agents/*.md` is the design source; the instructions stored on the Multica server are the runtime copy. Every edit requires:

1. Sync that agent's instructions to Multica.
2. Record the same `Instruction version` in the Multica agent description.
3. Verify the agent name, bound skills, max concurrency, and instruction version.
4. Run one side-effect-free smoke issue to verify status transitions, PR evidence reads, and the handoff.

Current versions: Coordinator `2026-08-13.13`; Builder `2026-08-13.9`; Reviewer `2026-08-13.9`; Inspector `2026-07-27.1`. A later change to a repo file still does not mean the server was synced.
