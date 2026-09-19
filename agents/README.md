# Agent Designs

Five agents, designed around the workflow in this repository. Four are squad members (Coordinator, Builder, Reviewer, Inspector). Planner is a workspace agent, invoked by parent status (`prd_draft`, `ready_for_slicing`, `needs_clarification`), not by squad assignment.

## Agents

- [`Planner`](./planner.md): requirement clarification, PRD, architectural decisions, vertical-slice issue creation. Not a squad member.
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

Planner creates children at `needs_triage`. Coordinator dispatches and drives stages.

Direct delegation rules:

- Builder → `in_review` + hand back to Coordinator.
- Reviewer:
  - Initial blocking review: creates one stage-feedback ticket for all unresolved PR threads, verifies it, closes reviewed implementation children, and assigns the feedback ticket to Builder at `todo`.
  - Cycle 1 still failing: updates the same feedback ticket and assigns it to Builder at `todo`.
  - Cycle 2 still failing: moves the same feedback ticket to `blocked` for human intervention.
  - If approved: hands back to Coordinator (`in_review` + assign Coordinator). Coordinator merges and closes stage children.
- Inspector → report/proposal only by default. `context` type may write approved files after human confirmation. Read-only types stay read-only. Dangerous actions require human confirmation.

Parallelism within stages is supported by promoting all independent stage tasks to `todo`. Execution across stages remains staged and ordered.

## Notification Rule

User @-mentions only Coordinator. Coordinator passes requester, originating chat surface, and parent link to Builder. Builder may notify the requester once on completion or blocker. Reviewer leaves one @Coordinator summary. Inspector writes one result packet + hands back.

GitHub comments use the workspace owner's account, so every Coordinator, Builder, and Reviewer PR review body, inline comment, general comment, and thread reply starts with its role prefix: `[coordinator]: `, `[builder]: `, or `[reviewer]: `. Multica issue comments do not need this prefix because Multica already records the agent identity.

Authority: dispatch = Coordinator, except Reviewer may dispatch the one canonical stage-feedback ticket and its first automatic retry. Execution = Builder. Completion notification = Builder. Re-review trigger = Coordinator only.

## Review Loop Budget

Initial review is cycle `0`. It may create one stage-feedback ticket spanning every original implementation slice. Builder fixes all unresolved Reviewer + human threads, then follow-up review verifies resolutions + new P0/P1 regressions only. Two automatic fix/re-review cycles are allowed. Cycle-1 failure automatically returns the same ticket to Builder; cycle-2 failure moves it to `blocked` for human intervention. The counter never resets after human resume.

## Human Gates

- **PRD confirmation.** Unconditional — even when the request arrives fully specified. A supplied spec is input, not approval.
- **Final PR review and merge** on GitHub. No gate before opening the Final PR: the PR IS the gate. Asking permission to create it is a gate-in-front-of-a-gate.
- **Parent `done` is human.** Builders land at `in_review`; Reviewer/Coordinator may close stage children only at the documented review gates.

The Builder PR (`work_branch → stage_branch`) is internal; Builder merges it. Reviewer reviews the stage PR (`stage_branch → source_branch`). After approval, Coordinator merges the stage PR. Once reviewed head is verified in `source_branch`, Coordinator opens the Final PR, runs mandatory final review, moves parent to `in_review`, and stops. `work_branch` is always cut from the current `stage_branch` tip.

## Status Model

Planning state lives in statuses, never labels. Branch on `status_category`, never `status_name` — category is the contract, name is for humans.

Four custom statuses (create in Settings → Issue Statuses) plus built-ins:

| Status | Category | Meaning |
|---|---|---|
| `needs_clarification` | `blocked` | Waiting on human answer |
| `blocked` | `blocked` | Review feedback waiting on human intervention, or an external blocker |
| `prd_draft` | `backlog` | Drafting the spec |
| `ready_for_slicing` | `backlog` | Spec done, not yet sliced |
| `needs_triage` | `backlog` | Sliced, not yet prioritised |
| `todo` | `todo` | Executable — `ready-for-agent` |
| `in_progress` | `in_progress` | Work underway |
| `in_review` | `in_review` | Delivered, awaiting acceptance |
| `done` | `done` | Human for parents; gated Reviewer/Coordinator closure for stage children |
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
- **One stage-feedback loop; Coordinator manages stage gates.** Reviewer creates one cross-ticket feedback child on initial failure and may dispatch it for two automatic cycles. Original implementation children close only after that ticket exists. Non-blocking/approved review handoffs and Builder completions return to Coordinator. Handback assignment is the wake signal and must never carry `--no-start` — suppressing it silently stalls the chain.
- **`--stage N` for dependencies.** Leader wakes when every sub-issue in a stage finishes (`done` or `cancelled`).
- **Review = own child issue assigned to Reviewer.** One review per stage + one mandatory final review over `source_branch`. No per-ticket review — stage boundaries are where mistakes get expensive.
- **No issue carries an open question.** Goal, scope, criteria, and every product decision settled before the issue exists. Non-blocking findings → proposals in comments, issues only when a human asks.
- **Children close at `done`; parent does not.** On initial failure Reviewer may close reviewed implementation children only after the canonical feedback child exists. Review + feedback children remain open, so the stage barrier cannot fire. Coordinator closes them after approval. `done` on parent stays human.
- **Parent status = leader's** while assigned to this squad.
- **Stage parallelism.** Parallelize independent tasks within the same stage by promoting them all to `todo`. Serial execution across stages.

## Branch And PR Safety

Everyone uses [`branch-pr-safety`](../skills/branch-pr-safety/SKILL.md). Branch/PR fields are internal control plane, not default user-facing.

Coordinator writes Delivery Context into each child before promotion: `repo`, `base_branch`, `source_branch`, `source_branch_status`, `issue_key`, `work_branch`, `stage_branch`, `builder_pr_target`, `final_pr_target`. `builder_pr_target` is `stage_branch`. `work_branch` is always cut from the current `stage_branch` tip.

Builder reports: change, PR, build/test conclusion, risks, `source_branch`. Coordinator gets refs/diff/files/checks from Git/PR.

Reviewer publishes: result, stage PR (or Final PR), blocking findings, non-blocking follow-ups, test gaps, residual risks. Each finding has a stable id.

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
Caveman register in ALL output — chat, issue bodies, comments, packets. Drop articles and filler. Fragments over sentences. [thing] [action] [reason]. Code symbols, paths, commands, error strings exact. Never restate spec, diff, or code in a comment — reference `file:line` or link. Packets = `key: value` lines, no prose paragraphs. One line per finding, risk, decision. Completion summaries <= 10 lines. Full clear prose only for security warnings and destructive actions.
```

## Skill Precedence

Agent instructions and issue/PR context override loaded skills. Skills provide methods and templates only — no extra permissions, no skipping gates, no changing dispatcher ownership.

## Deployment Sync Rule

`agents/*.md` is the design source; Multica server is the runtime copy. Every edit requires:

1. Sync instructions to Multica.
2. Record `Instruction version` in Multica agent description.
3. Verify name, bound skills, max concurrency, instruction version.
4. Run one side-effect-free smoke issue.

Current versions: Planner `2026-09-18.4`; Coordinator `2026-09-18.9`; Builder `2026-09-18.7`; Reviewer `2026-09-18.5`; Inspector `2026-09-18.2`.
