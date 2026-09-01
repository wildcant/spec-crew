# spec-crew

A workflow kit for running a squad of [Multica](https://github.com/multica-ai/multica)
agents over [Matt Pocock's engineering skills](https://github.com/mattpocock/skills).

Four agents — Coordinator, Builder, Reviewer, Inspector — with instructions,
a shared inter-agent contract, and the workspace skills they need. The agents
are the product; the skills stay vendored and unmodified.

## Attribution

This repository is a derivative of
[`goozyshi/multica-hub`](https://github.com/goozyshi/multica-hub), refactored
into English and stripped of its author's organisation-specific bindings. It is
not a GitHub fork, so this note is the provenance record. Upstream's design —
in particular adapting vendored skills purely from the agent instruction layer
— is the main thing worth inheriting.

To track upstream:

```bash
git remote add upstream https://github.com/goozyshi/multica-hub.git
```

`matt-skills/` is a verbatim mirror of Matt Pocock's MIT-licensed skills. See
[`matt-skills/README.md`](matt-skills/README.md) for the exact sync commit and
[`matt-skills/LICENSE`](matt-skills/LICENSE) for the licence.

## Layout

```text
agents/          Agent designs. The instruction payload you load into Multica.
  TEMPLATE.md    The file shape, plus the platform contract details that bite.
  README.md      The shared contract between agents: status model, handoffs, gates.
  squad.md       Squad instructions — leader briefing content, leader-only.
skills/          Workspace skills. Yours to edit.
matt-skills/     Vendored mirror of mattpocock/skills. Do not edit.
```

## The one rule

**Never edit anything under `matt-skills/`.**

Upstream vendored Matt's 25 skills verbatim — zero occurrences of "multica"
anywhere in that tree — and adapted them entirely from the agent instruction
layer. The Coordinator's instructions state the mechanism directly:

> These Agent instructions override every loaded skill. Skills provide methods
> and templates; they do not grant extra permissions or bypass workflow gates.

That design is what makes the mirror re-syncable: no fork to maintain, no merge
conflicts, and an upstream skill update is a directory replacement. If a skill
behaves wrongly for your workspace, constrain it from the agent that loads it.
Every behavioural change belongs in `agents/*.md`.

## Agent roster

| Agent | Job | Matt skills | Workspace skills |
|---|---|---|---|
| [Coordinator](agents/planner-coordinator.md) | The only dispatcher. Clarification, PRD, slicing, triage, dispatch. | `grilling`, `to-spec`, `to-tickets`, `triage` | `branch-pr-safety` |
| [Builder](agents/builder.md) | Implements issues in `todo`. Small steps, tests first. | `codebase-design`, `diagnosing-bugs`, `resolving-merge-conflicts`, `tdd` | `branch-pr-safety` |
| [Reviewer](agents/reviewer.md) | Reviews Builder output. Bugs, regressions, missing tests, risk. | `code-review`, `tdd` | `branch-pr-safety` |
| [Inspector](agents/inspector.md) | Routed inspections by `inspection_type`. Reports and proposals. | `grill-with-docs`, `handoff`, `writing-for-agents` | — |

Every agent runs `max_concurrent_tasks: 1`. That is deliberate serialisation:
where a plan needs real parallelism, prefer sub-agent fan-out inside one ticket
over concurrent tickets, so the work stays on one branch.

## Status model

Planning state lives in the issue status and nowhere else — statuses are
exclusive, labels are a set. Four custom statuses plus the built-ins:

| Status | Category | Meaning |
|---|---|---|
| `needs_clarification` | `blocked` | Coordinator is waiting on a human answer |
| `prd_draft` | `backlog` | Drafting the spec |
| `ready_for_slicing` | `backlog` | Spec done, not yet sliced |
| `needs_triage` | `backlog` | Sliced, not yet prioritised |
| `todo` | `todo` | Executable — native `todo` *is* `ready-for-agent` |
| `in_progress` | `in_progress` | Work underway |
| `in_review` | `in_review` | Delivered, awaiting human acceptance |
| `done` | `done` | Human only |

A status **key** is 1-32 characters of lowercase letters, digits, or underscore
— hyphens are rejected by the server. The keys above are the canonical ones this
kit expects; if your workspace already uses different keys for the same
categories, `bootstrap/` rewrites these instructions to match rather than
requiring you to rename anything.

The platform enforces this pipeline rather than convention: assigning an issue
that sits in a backlog-category status does not start a run, and moving it out
of backlog wakes the assignee. So the parked statuses are exactly the planning
ones, and reaching `todo` is the moment work becomes executable.

Agent instructions branch on **`status_category`**, never on the status name.
Issue JSON exposes `status`, `status_category`, and `status_name` separately; a
custom status inherits its category's behaviour in full, so the category is the
contract and the name is for humans.

Full contract, including handoffs, human gates, and squad mechanics:
[`agents/README.md`](agents/README.md).

## Chains by task type

### Vague request

```text
human input -> Coordinator bounded clarification -> draft PRD -> human confirmation
-> to-tickets slicing -> triage -> assign
```

- Matt skills: `grilling`, `grill-with-docs`, `domain-modeling`, `to-spec`, `to-tickets`, `triage`.
- Limit: at most 2 clarification rounds. Nothing reaches implementation before confirmation.
- Output: PRD, small issues, acceptance criteria, dependencies, and a status of `todo` or `needs_clarification`.

### Confirmed PRD

```text
PRD -> Coordinator slices vertical slices -> human confirms granularity
-> child issues created -> Builder implements each
```

- Matt skills: `to-spec`, `to-tickets`.
- Limit: every issue must be independently verifiable. Do not slice horizontally by frontend/backend/database.
- Output: issues small enough to run unattended.

### Small feature

```text
todo issue -> Builder -> tests -> Reviewer -> human acceptance and merge
```

- Matt skills: `tdd`, `codebase-design`.
- Limit: Builder does not run long clarifications. Missing information becomes a blocker.
- Output: code change, test results, risk notes.

### Bug fix

```text
bug issue -> Builder reproduces -> diagnosing-bugs isolates -> minimal fix
-> regression test -> Reviewer
```

- Matt skills: `diagnosing-bugs`, `tdd`.
- Limit: with no reproduction steps the issue goes to `needs_clarification`. Do not guess at a fix.
- Output: reproduction, root cause, fix, regression test.

### Code review

```text
Builder PR -> Coordinator creates a review child issue -> Reviewer packet
-> Coordinator decides fix / accept / merge
```

- Matt skills: `code-review`, `tdd`.
- Limit: prioritise bugs, regressions, and missing tests. Raise architecture only when the impact is real.
- Output: findings by severity, blocking items, follow-ups.

Review is its own child issue with its own run and fresh context — a stronger
isolation boundary than a sub-agent, and it removes author bias.

### Scheduled inspection

```text
Autopilot -> create_issue(inspection_type) -> Inspector -> report -> human handles exceptions
```

- Matt skills: `grill-with-docs`, `handoff`, `writing-for-agents`.
- `scope` may be a Multica project (covering every repo inside it) or a single repo.
- Limit: autopilot failures do not retry, so important inspections need their own success signal. Dangerous actions require human confirmation.
- Output: an inspection report, or follow-up issues.

## Branch and PR model

Three branch layers and two stacked PRs, enforced by
[`skills/branch-pr-safety`](skills/branch-pr-safety/SKILL.md):

```text
base_branch -> source_branch -> work_branch

Builder PR: work_branch   -> source_branch    (internal, reviewed by Reviewer)
Final PR:   source_branch -> final_pr_target  (the human review gate)
```

`source_branch` collects every child issue belonging to one goal, so the whole
goal reaches the human as a single pull request. Agents open the Final PR and
stop; a human reviews and merges it. `done` stays human.

## Loading these into your workspace

```bash
./bootstrap/bootstrap.sh --dry-run    # print every call, change nothing
./bootstrap/bootstrap.sh              # do it
```

That script does everything below, and is safe to re-run. See
[`bootstrap/README.md`](bootstrap/README.md) — in particular for what to do when
your workspace already uses different status keys, and for the three things that
have no CLI at all.

The manual equivalent, for reference. Nothing here is auto-applied:
`agents/*.md` is the design source, and Multica stores the instructions as an
opaque string, so editing a file in this repo changes nothing on the server.

1. **Create the four custom statuses** in Settings → Issue Statuses, with the
   categories in the table above. Category is what the platform acts on.

2. **Create each agent.** `name` and `runtime_id` are the only required fields.
   Paste the `## Instructions` fenced block verbatim — it is the literal
   payload and is written to stand alone.

   ```bash
   multica agent create --name Coordinator --runtime-id <runtime-id> \
     --instructions "$(...)" --max-concurrent-tasks 1
   ```

3. **Bind the skills separately.** `agent create` does not bind them, even
   though the HTTP body accepts `skill_ids`. Use `multica agent skill add`;
   `skill set` replaces every binding.

4. **Create the squad** with the Coordinator as leader and the other three as
   members, then set the squad's `instructions` from
   [`agents/squad.md`](agents/squad.md). Squad instructions reach the **leader
   only** — members never see them.

5. **Assign the parent issue to the squad.** Squads do not fan out: the
   assignment enqueues the leader, which then creates child issues and assigns
   each to a named member. Order dependencies with `--stage N`.

Details that bite — `description` never reaches the runtime and is capped at 255
code points, `conversation_starters` has no CLI flag, `agent copy` binds skills
atomically where `agent create` does not — are in
[`agents/TEMPLATE.md`](agents/TEMPLATE.md).

## Keeping the repo and the server in sync

`agents/*.md` is the design source; the server's stored `instructions` is the
runtime copy. Every edit requires syncing the instruction block to Multica,
recording the same `Instruction version` in the agent's description, verifying
name / bound skills / concurrency, and running one side-effect-free smoke issue.
