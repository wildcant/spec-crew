---
name: branch-pr-safety
description: Enforce safe branch and pull-request workflow for Coordinator, Builder, and Reviewer. Use whenever creating implementation issues, creating branches, opening PRs, reviewing PRs, or deciding PR targets.
---

# Branch PR Safety

Use this skill for any branch or PR operation.

## Branch Model

All implementation work uses three layers:

```text
base_branch -> source_branch -> work_branch
```

- `base_branch`: baseline branch. Default: `main`.
- `source_branch`: feature or hotfix branch that collects the work for one goal.
- `work_branch`: Builder-owned branch where code changes happen.

PRs are stacked in two stages:

```text
Builder PR: work_branch   -> source_branch
Final PR:   source_branch -> final_pr_target
```

Why two stages and not one: `source_branch` collects every child issue that
belongs to the same goal. The Builder PR is an internal integration step,
reviewed by the Reviewer agent on its own issue. The Final PR is the single
human-facing pull request for the whole goal.

- `builder_pr_target` must equal `source_branch`.
- `final_pr_target` is the branch the completed goal lands on. Default:
  `base_branch`. Workspaces that deploy from a dedicated branch set it to that
  branch instead.
- Builder creates only the Builder PR.
- Coordinator or a human creates the Final PR after internal review and human
  authorisation.
- Nobody merges the Final PR except a human.

## Required Issue Fields

Every implementation issue must include:

```md
repo:
base_branch:
source_branch:
source_branch_status:
issue_key:
work_branch:
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
  does not exist, Builder must create it from latest `base_branch`.
- `must_exist`: existing integration, feature, or hotfix branch. If remote
  `source_branch` does not exist, Builder must stop and report a blocker.

## Visibility Rules

Branch/PR fields are internal control-plane data.

- Coordinator must write them into the implementation child issue.
- Builder must use them to create branches and PRs safely.
- Reviewer must use them to verify branch and PR safety.
- Normal user-facing summaries should not list `base_branch`, `source_branch`,
  `source_branch_status`, `work_branch`, `builder_pr_target`, or
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

If the user does not specify a branch:

```md
repo: <repo name or remote URL>
base_branch: main
source_branch: feature/<short-slug> or feature/v<version>-<short-slug>
source_branch_status: create_if_missing
issue_key: <visible issue key>
work_branch: agent/<issue-key>-<short-slug>
builder_pr_target: same as source_branch
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
builder_pr_target: same as source_branch
final_pr_target: main
```

If the work is an online/hotfix issue, use `hotfix/...`, not `feature/...`.

Coordinator must create or identify the child issue first, read its visible
`issue_key`, then fill `work_branch` before assigning Builder. If the visible
issue key is unavailable, stop and mark the issue blocked; do not invent a
branch name.

## Builder Rules

Builder must follow this order:

1. Read all required branch fields, including `repo` and `source_branch_status`.
2. Verify the selected repo matches `repo`.
3. Verify `builder_pr_target == source_branch`.
4. Fetch latest `base_branch`.
5. Check whether `source_branch` exists.
6. If `source_branch_status = create_if_missing` and remote `source_branch` does
   not exist, create it from latest `base_branch` and push it.
7. If `source_branch_status = must_exist` and remote `source_branch` does not
   exist, stop and report a blocker.
8. Fetch latest `source_branch`.
9. Create `work_branch` from `source_branch`.
10. Commit only to `work_branch`.
11. Open the Builder PR: `work_branch -> source_branch`.
12. On the Builder PR, enabling "delete branch after merge" is allowed and
    preferred, because the branch it deletes is `work_branch`.
13. Do not open the Final PR.

Builder must stop and ask a human or the Coordinator if:

- Required branch fields are missing.
- The selected repo does not match `repo`.
- `builder_pr_target != source_branch`.
- `issue_key` is missing or is not the visible issue key.
- `work_branch` does not start with `agent/<issue_key>-`.
- `work_branch` contains a UUID, project id, or internal task id instead of the
  visible issue key.
- `source_branch_status` is neither `create_if_missing` nor `must_exist`.
- `source_branch_status = must_exist` and remote `source_branch` does not exist.
- The tool defaults the PR base to `main` or to `base_branch`.
- The tool cannot control the PR base.
- The PR diff includes unrelated changes.
- The operation would commit to `base_branch`, `source_branch`, `main`, a
  release branch, or a shared integration branch.

On GitHub the PR base is the target branch. `gh pr create --base <branch>` sets
it explicitly; never rely on the repository default, which is `main`.

## Final PR Rules

The Final PR is:

```text
source_branch -> final_pr_target
```

- Create it only after internal review passes and a human authorises it.
- Do not delete `source_branch` after the final merge.
- The Final PR is the human review gate. Agents open it and stop. A human
  reviews and merges it; no agent merges a PR targeting `main`, `base_branch`,
  or a protected branch.

## Reviewer Rules

Reviewer checks branch safety as part of review:

- The Builder PR base is `source_branch`.
- Builder did not open the Final PR.
- Builder changed only `work_branch`.
- The Builder PR's delete-branch-on-merge setting, if enabled, deletes only
  `work_branch`.
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
builder_pr_target: feature/guild-invite
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
builder_pr_target: feature/v2.42-guild-invite
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
builder_pr_target: feature/v2.42-search-rework
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
builder_pr_target: hotfix/v2.42-login
final_pr_target: main
```
