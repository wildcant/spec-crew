---
name: merged-branch-cleanup
description: Scan for stale branches already merged into main, grouped by repository with an activity tier and a checklist, to support a human decision on deletion. Deletion runs only after per-branch human confirmation.
---

## Check List

1. List every remote branch already merged into `main` (or `master`) in the target repository.
2. Keep only work branches as candidates — short-lived prefixes such as `feature/*`, `feat/*`, `fix/*`, `bugfix/*`, `temp/*`, `chore/*`, `refactor/*`, `experiment/*`, or unprefixed non-trunk branches. Exclude long-lived branches (trunk, environment, and release lines such as `main`, `master`, `develop`, `release/*`, `hotfix/*`) semantically rather than by a hardcoded allowlist — the test is whether the branch is a persistent branch or a one-off work branch in this team's workflow.
3. For each candidate branch, collect:
   - Last commit date, author, and commit message summary
   - When it was merged into main (from the PR record or the merge commit)
   - Activity tier:
     - 🟢 changed within 7 days (shown, not flagged as stale)
     - 🟡 changed 8–30 days ago
     - 🔴 no change for over 30 days
4. Threshold filter: last commit ≤ 14 days → show it, but keep it out of "suggest deleting".
5. Group by repository. For each branch show: branch name, last commit date, author, activity tier, recommendation.

## Thresholds

- Stale: merged into main + last commit > 14 days ago
- Activity tiers: 7 days / 30 days
- Excluded: long-lived branches (trunk / environment / release lines), identified semantically. Only work branches become candidates.

## Report Format

One block per repository:

```
### <repository>

| Branch   | Last commit | Author  | Activity  | Recommendation |
|----------|-------------|---------|-----------|----------------|
| feat/xxx | 2026-06-01  | alice   | 🔴 >30d   | safe to delete |
| feat/yyy | 2026-06-20  | bob     | 🟡 >14d   | safe to delete |

Deletion checklist, pending confirmation:
- [ ] `feat/xxx`
- [ ] `feat/yyy`
```

Summary lines:

- N stale branches across M repositories
- K long-lived branches excluded
- **Deletion runs only after a human confirms each branch explicitly**

## Safety Rules

- Phase 1 is a read-only scan plus recommendations.
- Deleting a branch is a dangerous action. It requires its own explicit human confirmation before Phase 2 begins.
- Long-lived branches never enter the deletion candidate list, and are never deleted even if a user writes one into the confirmation list.
- Re-verify each branch's current state immediately before deleting it, in case someone else already handled it.
- If a branch's state changed after the proposal, stop and re-confirm.
- Delete only the branches named in this run's confirmation. Never reuse a confirmation across issues.

## Phase 2 — Execute the deletion

**Trigger**: the user replies on the issue with an explicit confirmation (`approved`, `please delete`, `go ahead`) naming specific branches, or referencing branches ticked in the checklist.

**Steps**, in order, run independently per repository:

1. `git fetch --prune origin` to refresh remote state.
2. For each branch queued for deletion, verify:
   - The branch still exists on the remote
   - Its tip is still reachable from `origin/main` (`git merge-base --is-ancestor`)
   - It is not a long-lived branch (trunk / environment / release line)
   - It has no open PR
3. Checks pass → run `git push origin --delete <branch>` and record the result.
4. Checks fail → skip it, state the specific reason, and do not delete.
5. After every branch is handled, print a summary:
   - ✅ deleted N (list the branch names)
   - ⏭️ skipped M (list the branch names and reasons)
6. On any error during execution, stop the remaining deletions immediately and report it.
