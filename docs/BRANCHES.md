# Branches — history and rules

**`main` is the only source of truth.** Every session (any Claude account, Codespace, laptop, other AI) starts from
`main` and ends by merging its branch back into `main` through a pull request. A branch that is not merged is
invisible to the next session — that is how 15 Nov 2026 started from a 3-week-old `main`.

## Rules for every session
1. **Start:** `git fetch origin`, then check for unmerged work: `git branch -r --no-merged origin/main`.
   Anything listed → read its last commits and PROGRESS, merge it into your branch first (or ask the owner).
2. **Work** on the branch your session names (cloud: `claude/<name>`; Codespace/laptop: `work/<yyyy-mm-dd>-<topic>`).
   Conventional commits; merge commits say which branch came in and what it carried.
3. **End of every working day:** open a PR `<branch> → main` (merge commit, not squash, so the history stays readable),
   the owner merges it, then add a row to the table below. Never push `main` directly.
4. **One active branch at a time.** A second parallel session must branch from the first session's branch and merge back
   into it, or wait.
5. After a merge, a branch is finished. Continue on a fresh branch from `main` (same name allowed if the session insists).

## History (oldest first)
| # | Branch | Dates | What it carried | State |
|---|---|---|---|---|
| 1 | `main` (fork of upstream `0.92.3`) | 20 Oct 2026 | pinned upstream release, deleted upstream workflows (ledger #4) | base |
| 2 | `claude/funny-keller-x6sgy1` | 20–26 Oct 2026 | Phases 0–5 (merged by PR #1 on 22 Oct), then Phases 6, 7 and the Phase 9 build + Oracle shared-server run S1–S6 | fully contained in #3 |
| 3 | `claude/blissful-lovelace-ltnlm9` | 15 Nov 2026 | merged #2, four fixes (secret file modes, `doctor --remote`, pin check, backup lock test), independence plan + I.2 image mirror, I.3 piece pack | fully contained in #4 |
| 4 | `claude/ecstatic-keller-dxgivp` | 15 Nov 2026 | merged #3, launch-week plan, Chrome log T0–T4 (local Claude-in-Chrome session), practice client Threadline BD, learning track, this file | merged into `main` by PR (15 Nov 2026) |

Branches #2 and #3 are fully inside `main` after #4's merge; they can be deleted on GitHub (the commits stay in `main`).
