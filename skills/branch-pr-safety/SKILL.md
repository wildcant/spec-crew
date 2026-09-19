---
name: branch-pr-safety
description: Enforce the staged branch and pull-request workflow for Coordinator, Builder, and Reviewer. Use whenever creating implementation issues, creating branches, opening PRs, reviewing PRs, or deciding PR targets.
---

# Branch PR Safety

Use this skill for any branch or PR operation.

## Branch Model

All implementation work uses four layers:

```text
base_branch -> source_branch -> stage_branch -> work_branch
```

- `base_branch`: baseline branch. Default: `main`.
- `source_branch`: feature or hotfix branch that collects every completed stage for one goal.
- `stage_branch`: per-stage integration branch. Cut from `source_branch` at stage start. Never cut from a previous stage branch.
- `work_branch`: Builder-owned branch. Cut from the current `stage_branch` tip so already-merged sibling work exists.

PRs are stacked in three layers:

```text
Builder PR: work_branch   -> stage_branch     (Builder merges own PR)
Stage PR:   stage_branch  -> source_branch    (the review gate)
Final PR:   source_branch -> final_pr_target  (the human gate)
```

Why three layers: `source_branch` collects the whole goal for one human-facing PR. Review happens once per stage on the stage PR, not on each sub-ticket PR. Sub-ticket PRs merge into `stage_branch` without an individual Reviewer pass; nothing reaches `source_branch` unreviewed.

**Invariant: a stage branch is always cut from `source_branch`, never from a previous stage branch.** Stage N+1 sees stage N work only because the stage N PR was merged into `source_branch` first.

- `builder_pr_target` must equal `stage_branch`.
- `final_pr_target` is the branch the completed goal lands on. Default: `base_branch`. Workspaces that deploy from a dedicated branch set it to that branch instead.
- Builder creates only the Builder PR, then merges that PR into `stage_branch`.
- Coordinator creates the stage PR at stage start and the Final PR after the last stage merges.
- Nobody merges the Final PR except a human.
- Nobody merges a stage PR except Coordinator, and only after Reviewer approval with `review_head_ref` still equal to the stage branch tip.

## Required Issue Fields

Every implementation issue must include:

```md
repo:
base_branch:
source_branch:
source_branch_status:
issue_key:
work_branch:
stage_branch:
builder_pr_target:
final_pr_target:
```

Do not start implementation if any field is missing or inconsistent.

`repo` may be any unambiguous repository identifier:

- Multica project name.
- Repository name.
- Remote URL.

If the workspace or issue context exposes exactly one configured
project/repository, Coordinator may infer `repo` from it. Do not ask for a repo
address in that case.

Allowed `source_branch_status` values:

- `create_if_missing`: new feature or hotfix branch. If remote `source_branch`
  does not exist at stage-1 start, Coordinator creates it from latest
  `base_branch`.
- `must_exist`: existing integration, feature, or hotfix branch. If remote
  `source_branch` does not exist, Coordinator stops and reports a blocker.

## Visibility Rules

Branch/PR fields are internal control-plane data.

- Coordinator must write them into the implementation child issue.
- Builder must use them to create branches and PRs safely.
- Reviewer must use them to verify branch and PR safety.
- Normal user-facing summaries should not list `base_branch`, `source_branch`,
  `source_branch_status`, `stage_branch`, `work_branch`, `builder_pr_target`, or
  `final_pr_target`.
- User-facing summaries may say `Branch safety checked`.
- Show detailed branch/PR fields only when the user asks, a blocker occurs, a
  safety risk exists, or a human decision is required.

## Branch Naming

New feature work:

```text
feature/<short-slug>
feature/v<version>-<short-slug>
```

Production or online hotfix:

```text
hotfix/<short-slug>
hotfix/v<version>-<short-slug>
```

Stage branch:

```text
stage/<N>-<short-slug>
```

Builder work branch:

```text
agent/<issue-key>-<short-slug>
```

`issue_key` means the human-visible issue key, such as `PROJ-338`.

- Use the visible Multica issue key.
- Do not use project ids.
- Do not use UUIDs.
- Do not use internal task ids.
- `work_branch` must start with `agent/<issue_key>-`.
- `work_branch` is always cut from the current `stage_branch` tip.

Slug rules:

- 2-4 words.
- Lowercase kebab-case.
- Keep it short.
- If a source branch name already exists for unrelated work, add the issue key:

```text
feature/v<version>-<issue-key>-<short-slug>
hotfix/v<version>-<issue-key>-<short-slug>
```

## Coordinator Rules

Coordinator decides branch fields before assigning Builder.

Coordinator owns `source_branch` and `stage_branch`. At stage-1 start, if
`source_branch_status` is `create_if_missing` and remote `source_branch` does
not exist, Coordinator creates it from latest `base_branch` and pushes it. Then
Coordinator cuts `stage_branch` from the `source_branch` tip and opens a draft
stage PR `stage_branch -> source_branch`. Builder never creates `source_branch`
or `stage_branch`.

If the user does not specify a branch:

```md
repo: <repo name or remote URL>
base_branch: main
source_branch: feature/<short-slug> or feature/v<version>-<short-slug>
source_branch_status: create_if_missing
issue_key: <visible issue key>
work_branch: agent/<issue-key>-<short-slug>
stage_branch: stage/<N>-<short-slug>
builder_pr_target: stage_branch
final_pr_target: main
```

If the user specifies an existing feature/hotfix branch:

```md
repo: <repo name or remote URL>
base_branch: <existing feature/hotfix branch>
source_branch: <existing feature/hotfix branch>
source_branch_status: must_exist
issue_key: <visible issue key>
work_branch: agent/<issue-key>-<short-slug>
stage_branch: stage/<N>-<short-slug>
builder_pr_target: stage_branch
final_pr_target: main
```

If the work is an online/hotfix issue, use `hotfix/...`, not `feature/...`.

Coordinator must create or identify the child issue first, read its visible
`issue_key`, then fill `work_branch` before assigning Builder. If the visible
issue key is unavailable, stop and mark the issue blocked; do not invent a
branch name.

## Builder Rules

Builder must follow this order:

1. Read all required branch fields, including `repo`, `stage_branch`, and
   `source_branch_status`.
2. Verify the selected repo matches `repo`.
3. Verify `builder_pr_target == stage_branch`.
4. Fetch latest `base_branch`.
5. Confirm remote `source_branch` exists. If it does not, stop and report a
   blocker — Coordinator creates `source_branch`, not Builder.
6. Confirm remote `stage_branch` exists. If it does not, stop and report a
   blocker — Coordinator cuts `stage_branch` at stage start, not Builder.
7. Fetch latest `stage_branch`.
8. Create `work_branch` from the current `stage_branch` tip.
9. Commit only to `work_branch`.
10. Open the Builder PR: `work_branch -> stage_branch`.
11. Before merging, update `work_branch` with the latest `stage_branch` and
    resolve conflicts.
12. Merge your own Builder PR into `stage_branch`. That is the only merge
    Builder performs.
13. On the Builder PR, enabling "delete branch after merge" is allowed and
    preferred, because the branch it deletes is `work_branch`.
14. Do not open the stage PR or the Final PR.
15. Do not merge the stage PR or the Final PR.

Builder must stop and ask a human or the Coordinator if:

- Required branch fields are missing.
- The selected repo does not match `repo`.
- `builder_pr_target != stage_branch`.
- `issue_key` is missing or is not the visible issue key.
- `work_branch` does not start with `agent/<issue_key>-`.
- `work_branch` contains a UUID, project id, or internal task id instead of the
  visible issue key.
- `source_branch_status` is neither `create_if_missing` nor `must_exist`.
- Remote `source_branch` or `stage_branch` does not exist.
- The tool defaults the PR base to `main`, `base_branch`, or `source_branch`.
- The tool cannot control the PR base.
- The PR diff includes unrelated changes.
- The operation would commit to `base_branch`, `source_branch`, `main`, a
  release branch, or a shared integration branch, except the one allowed merge
  of the Builder PR into `stage_branch`.

On GitHub the PR base is the target branch. `gh pr create --base <branch>` sets
it explicitly; never rely on the repository default, which is `main`.

## Stage PR Rules

The Stage PR is:

```text
stage_branch -> source_branch
```

- Coordinator opens it as a draft at stage start.
- Reviewer reviews this PR, not individual Builder PRs.
- Coordinator marks it ready when every stage implementation child is
  `in_review`, records `review_base_ref` (`source_branch` tip SHA) and
  `review_head_ref` (stage branch tip SHA), then dispatches Reviewer.
- Coordinator merges it only after Reviewer approval, and only when
  `review_head_ref` still equals the stage branch tip.
- After merge, Coordinator deletes `stage_branch`.

## Final PR Rules

The Final PR is:

```text
source_branch -> final_pr_target
```

- Create it after the last stage PR is merged into `source_branch`.
- Do not ask permission to open it. The Final PR is the human review gate.
- Do not delete `source_branch` after the final merge.
- No agent merges a PR targeting `main`, `base_branch`, `final_pr_target`, or a
  protected branch.

## Reviewer Rules

Reviewer checks branch safety as part of review:

- The review unit is the stage PR (`stage_branch -> source_branch`), or the
  Final PR for a final review.
- Every sub-ticket PR bases on `stage_branch` and is merged.
- Builder did not open the stage PR or the Final PR.
- Builder changed only `work_branch`, except the one merge into `stage_branch`.
- Delete-branch-on-merge, if enabled, deletes only `work_branch` or the stage
  branch.
- No PR bases on `main` or `base_branch` without explicit human authorisation.

## Examples

New feature, no version:

```md
repo: <repo-name-or-remote-url>
base_branch: main
source_branch: feature/guild-invite
source_branch_status: create_if_missing
issue_key: PROJ-12
work_branch: agent/PROJ-12-guild-invite
stage_branch: stage/1-guild-invite
builder_pr_target: stage/1-guild-invite
final_pr_target: main
```

New feature, versioned:

```md
repo: <repo-name-or-remote-url>
base_branch: main
source_branch: feature/v2.42-guild-invite
source_branch_status: create_if_missing
issue_key: PROJ-12
work_branch: agent/PROJ-12-guild-invite
stage_branch: stage/1-guild-invite
builder_pr_target: stage/1-guild-invite
final_pr_target: main
```

Existing feature branch:

```md
repo: <repo-name-or-remote-url>
base_branch: feature/v2.42-search-rework
source_branch: feature/v2.42-search-rework
source_branch_status: must_exist
issue_key: PROJ-13
work_branch: agent/PROJ-13-invite-filter
stage_branch: stage/1-invite-filter
builder_pr_target: stage/1-invite-filter
final_pr_target: main
```

Online hotfix:

```md
repo: <repo-name-or-remote-url>
base_branch: main
source_branch: hotfix/v2.42-login
source_branch_status: create_if_missing
issue_key: PROJ-14
work_branch: agent/PROJ-14-login
stage_branch: stage/1-login
builder_pr_target: stage/1-login
final_pr_target: main
```
