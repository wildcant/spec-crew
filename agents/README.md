# Agent Designs

Five agents, designed around the workflow in this repository.

## Agents

- [`Planner`](./planner.md): requirement clarification, PRD, architectural decisions, vertical-slice issue creation.
- [`Coordinator`](./coordinator.md): the only dispatcher. Triage, dispatch, review orchestration, Final PR.
- [`Builder`](./builder.md): implements issues in `todo`. Small steps, tests first.
- [`Reviewer`](./reviewer.md): reviews implementation results. Finds bugs, regressions, missing tests, risk.
- [`Inspector`](./inspector.md): general-purpose inspection agent. Routes skills on `inspection_type`; ships `todo-scan` (read-only) as a built-in example. `scope` = Multica project or single repo. Supports self-service bootstrap for new inspection types.

## Final Skills

- `Planner`: Matt `grilling`, `to-spec`, `to-tickets`
- `Coordinator`: Matt `triage`; Workspace `branch-pr-safety`
- `Builder`: Matt `codebase-design`, `diagnosing-bugs`, `resolving-merge-conflicts`, `tdd`; Workspace `branch-pr-safety`
- `Reviewer`: Matt `code-review`, `tdd`; Workspace `branch-pr-safety`
- `Inspector`: Matt `grill-with-docs`, `handoff`, `writing-for-agents`

## Dispatch Rule

Planner creates children at `needs_triage`. Only Coordinator dispatches and reassigns.

Members never dispatch each other:

- Builder → `in_review` + hand back to Coordinator.
- Reviewer → writes `review_result` (packet content, not status) + hand back. Never advances acceptance or merges.
- Inspector → report/proposal only by default. `context` type may write approved files after human confirmation. Read-only types stay read-only. Dangerous actions require human confirmation.

Builder work on the same repo is serial. Parallel only with confirmed isolated worktrees.

## Notification Rule

User @-mentions only Coordinator. Coordinator passes requester, originating chat surface, and parent link to Builder. Builder may notify the requester once on completion or blocker. Reviewer leaves one @Coordinator summary. Inspector writes one result packet + hands back.

Authority: dispatch = Coordinator only. Execution = Builder. Completion notification = Builder. Re-review trigger = Coordinator only.

## Review Loop Budget

One review run = one round. Builder fixes all findings, hands back once. Follow-up review verifies resolution + new P0/P1 regressions only. Max one automatic review-fix cycle per issue; second `changes-requested` → `needs_clarification` with human decision needed.

## Human Gates

- **PRD confirmation.** Unconditional — even when the request arrives fully specified. A supplied spec is input, not approval.
- **Final PR review and merge** on GitHub. No gate before opening the Final PR: the PR IS the gate. Asking permission to create it is a gate-in-front-of-a-gate.
- **`done` is human.** Agents land at `in_review`.

The Builder PR (`work_branch → source_branch`) is internal. After Reviewer approval, Coordinator merges where policy allows. Once reviewed head is verified in `source_branch`, Coordinator opens the Final PR, runs mandatory final review, moves parent to `in_review`, and stops.

## Status Model

Planning state lives in statuses, never labels. Branch on `status_category`, never `status_name` — category is the contract, name is for humans.

Four custom statuses (create in Settings → Issue Statuses) plus built-ins:

| Status | Category | Meaning |
|---|---|---|
| `needs_clarification` | `blocked` | Waiting on human answer |
| `blocked` | `blocked` | Waiting on something non-decisional |
| `prd_draft` | `backlog` | Drafting the spec |
| `ready_for_slicing` | `backlog` | Spec done, not yet sliced |
| `needs_triage` | `backlog` | Sliced, not yet prioritised |
| `todo` | `todo` | Executable — `ready-for-agent` |
| `in_progress` | `in_progress` | Work underway |
| `in_review` | `in_review` | Delivered, awaiting acceptance |
| `done` | `done` | Human only |
| `cancelled` | `cancelled` | Dropped |

Key: `1-32` chars, lowercase + digits + underscore (no hyphens). `bootstrap/` rewrites instructions to match existing workspace keys.

Why it works: backlog-category assignment doesn't start a run; moving out of backlog wakes the assignee. `todo` is the exact moment work becomes executable. No post-implementation status vocabulary — handoffs use child-issue ownership + comment packets.

```text
needs_clarification (blocked, any point)
prd_draft -> ready_for_slicing -> needs_triage   (backlog: parked)
-> todo -> in_progress -> in_review -> done
```

## Squad Mechanics

Coordinator is squad leader. The platform does not do these:

- **No fan-out.** Squad assignment enqueues leader only. Coordinator creates children and assigns each to a named member.
- **Members never assign to each other.** Handback assignment is the wake signal and must never carry `--no-start` — suppressing it silently stalls the chain. This is the single most load-bearing line in the contract.
- **`--stage N` for dependencies.** Leader wakes when every sub-issue in a stage finishes.
- **Review = own child issue assigned to Reviewer.** One review per stage + one mandatory final review over `source_branch`. No per-ticket review — stage boundaries are where mistakes get expensive.
- **No issue carries an open question.** Goal, scope, criteria, and every product decision settled before the issue exists. Non-blocking findings → proposals in comments, issues only when a human asks.
- **Children close at `done`; parent does not.** Coordinator closes stage children after review approves — the stage barrier requires `done`/`cancelled` category. Members never close their own work. `done` on parent stays human.
- **Parent status = leader's** while assigned to this squad.
- **Serial execution.** `max_concurrent_tasks: 1`. Sub-agent fan-out inside one ticket for parallelism.

## Branch And PR Safety

Everyone uses [`branch-pr-safety`](../skills/branch-pr-safety/SKILL.md). Branch/PR fields are internal control plane, not default user-facing.

Coordinator writes Delivery Context into each child before promotion: `repo`, `base_branch`, `source_branch`, `source_branch_status`, `issue_key`, `work_branch`, `builder_pr_target`, `final_pr_target`.

Builder reports: change, PR, build/test conclusion, risks, `source_branch`. Coordinator gets refs/diff/files/checks from Git/PR.

Reviewer publishes: result, Builder PR, blocking findings, non-blocking follow-ups, test gaps, residual risks. Each finding has a stable id.

Inspector publishes: type, scope, result, action required, human approval, findings, evidence, actions, follow-up refs, decisions.

`work_branch` = `agent/<issue_key>-<short-slug>`. New requirements default to `source_branch_status: create_if_missing`.

## Build Check

Builder runs the build for UI changes before `in_review`. Where a test seam exists, Builder adds coverage and Reviewer reviews for gaps. Where no seam exists, Coordinator records evidence and fallback verification; Builder skips framework setup; Reviewer treats the gap as risk.

## Context Budget

Every run has a hard token ceiling — quota exhaustion is a silent failure. Every agent enforces:

- **Targeted tests only.** Specific file + `-t '<name>'`. Broad runs → CI or own issue.
- **Surgical reads.** `rg -n` → `sed -n` line ranges. Never whole specs/PRDs/large sources.
- **Filtered output.** `--stat`, `tail -30`, `grep -E`, `--reporter=dot`. No lockfiles or build logs.
- **15-25 steps.** Planner sizes slices to fit; Coordinator refuses oversized children; Builder hands back as re-slicing blocker.
- **Bail before ceiling.** Builder commits partial work with status comment.

Builder runs at `medium` thinking — high thinking multiplies output tokens per step across a 25-step run.

## Shared Communication Instruction

```md
Terse English. [thing] [action] [reason]. Code symbols exact. No filler or hedging.
Clear prose for security warnings and destructive actions.
```

## Skill Precedence

Agent instructions and issue/PR context override loaded skills. Skills provide methods and templates only — no extra permissions, no skipping gates, no changing dispatcher ownership.

## Deployment Sync Rule

`agents/*.md` is the design source; Multica server is the runtime copy. Every edit requires:

1. Sync instructions to Multica.
2. Record `Instruction version` in Multica agent description.
3. Verify name, bound skills, max concurrency, instruction version.
4. Run one side-effect-free smoke issue.

Current versions: Planner `2026-09-14.3`; Coordinator `2026-09-14.3`; Builder `2026-09-14.2`; Reviewer `2026-09-14.2`; Inspector `2026-09-14.2`.
