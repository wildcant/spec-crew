# `matt-skills/` — vendored copy of `mattpocock/skills`

This directory is a **verbatim, read-only mirror** of Matt Pocock's open-source
skills collection. It is not part of this repository's own source.

## Provenance

| | |
|---|---|
| Upstream project | [`mattpocock/skills`](https://github.com/mattpocock/skills) |
| Author | Matt Pocock |
| Licence | MIT — see [`LICENSE`](./LICENSE) |
| Sync commit | [`84fdeff`](https://github.com/mattpocock/skills/commit/84fdeffd12f2ee307994d1eb6feb48173b6e0502) (2026-08-06) |
| Vendored subset | `skills/engineering/` and `skills/productivity/` only |
| Excluded from the mirror | `skills/deprecated/`, `skills/in-progress/`, `skills/misc/` |

The mirror was inherited from [`goozyshi/multica-hub`](https://github.com/goozyshi/multica-hub),
which vendored it without a licence file or attribution. Both are restored here:
MIT requires the copyright notice and permission notice be retained in all copies.

`matt-skills/engineering/` and `matt-skills/productivity/` are byte-identical to
`skills/engineering/` and `skills/productivity/` at the sync commit above.

## Do not edit anything in this directory

This is the single most important convention in the repository, and it is
inherited deliberately from upstream.

Every behavioural adaptation belongs in `agents/*.md` — the agent instructions
layer, which explicitly overrides any loaded skill:

> These Agent instructions override every loaded skill. Skills provide methods
> and templates; they do not grant extra permissions or bypass workflow gates.

Adapting from the instruction layer instead of forking the skills means:

- the mirror survives upstream skill updates,
- there is no fork to maintain and no merge conflicts to resolve,
- a re-sync is a directory replacement, not a rebase.

If a skill's behaviour is wrong for your workspace, constrain it from the agent
that loads it. Do not patch the skill.

## Re-syncing

```bash
git clone https://github.com/mattpocock/skills.git /tmp/matt-skills-upstream
rm -rf matt-skills/engineering matt-skills/productivity
cp -R /tmp/matt-skills-upstream/skills/engineering matt-skills/engineering
cp -R /tmp/matt-skills-upstream/skills/productivity matt-skills/productivity
```

Then update the sync commit in the table above, and review `agents/*.md` for
skill names or behaviours that changed upstream.

## Verifying the mirror is unmodified

```bash
diff -r matt-skills/engineering <upstream-checkout>/skills/engineering
diff -r matt-skills/productivity <upstream-checkout>/skills/productivity
# expect: no output
```
