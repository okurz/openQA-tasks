# 193_oqa2_auto_merge_documentation_prs

Auto-merge "Update documentation" PRs on `gh-pages` via mergify, mirroring the
existing auto-merge rules for `chore(deps): Dependency cron` PRs (author
`os-autoinst-bot`) and `dependabot[bot]` PRs.

## Facts established (read-only research, 2026-11-13, working copy oqa2)

- Docs PRs are produced by `tools/ci/build-docs` + `tools/generate-documentation`
  (CircleCI scheduled job): bot pushes `gh-pages-YYMMDDHHMMSS` to the
  `os-autoinst-bot/openQA` fork and opens a PR against `os-autoinst:gh-pages`
  with title `Update documentation to commit <sha>` (e.g. PR #8106).
- Auto-merge today lives in `.mergify.yml`:
  - `automatic merge for dependency bot updates`: `base=master` (via
    `*core_checks`), `author~=^os-autoinst-bot$`, `#check-success>=39`,
    `#check-pending=0`, `#check-failure=0`, `linear-history`, `method: merge`.
  - `automatic merge for dependabot updates`: `author=dependabot[bot]`,
    `base=master`, `method: squash`.
- Docs PRs target `gh-pages`, so `*core_checks` (which pins `base=master`,
  `codecov/*` statuses, `#check-success>=39`) can never match them — they are
  merged manually by okurz (e.g. #8106, #8094).
- Checks on a docs PR (verified with `gh pr checks`/`statusCheckRollup` for
  #8106 and #8094, identical sets): 5 entries — `Checklist job`,
  `Report OBS URL`, `OBS SCM/CI Workflow Integration started`,
  `continuous-integration/obs-helper`, `Summary` (the last is mergify's own
  check, present only once mergify has evaluated). So at rule-evaluation time
  there are 4 external checks.
- `gh-pages` is not a protected branch (`gh api
repos/os-autoinst/openQA/branches/gh-pages/protection` → 404), so mergify
  needs no extra permissions; the bot branch is a single commit on top of
  `gh-pages` (linear history).
- No repo test covers `.mergify.yml`; the automated gate is yamllint via
  `make test-checkstyle` (`test-checkstyle-standalone` includes `test-yaml`),
  the behavioral gate is a live docs PR.

## Design decisions

1. New mergify rule `automatic merge for documentation bot updates` with
   standalone conditions (must NOT reuse the `*base_checks`/`*core_checks`
   anchors, they pin `base=master` and check counts that a `gh-pages` PR can
   never reach):

   ```yaml
   - name: automatic merge for documentation bot updates
     conditions:
       - base=gh-pages
       - author~=^os-autoinst-bot$
       - title~=^Update documentation to commit
       - '#check-failure=0'
       - '#check-pending=0'
       - '#check-success>=4'
       - linear-history
     actions:
       merge:
         method: merge
   ```

   - `#check-success>=4`: the four external checks (Checklist, Report OBS URL,
     OBS SCM started, obs-helper); `#check-pending=0` blocks until all
     complete, so the threshold cannot be satisfied by mergify's own `Summary`
     check alone.
   - `title~=^Update documentation to commit` scopes the rule to generated
     docs PRs; a human PR from the bot's fork targeting `gh-pages` is not
     auto-merged.
   - `method: merge` matches how dependency-cron PRs merge and how `gh-pages`
     history looks today (merge commits).
   - No review requirement, same trust model as the dependency-cron rule.

2. Staged rollout: commit 1 ships the rule with `actions: comment` only
   (observe, no auto-merge); commit 2 flips it to `actions: merge` after
   observing at least one live docs PR with 4 passing checks. Revert = plain
   `git revert` of the respective commit.
3. PR implementing the rule goes through normal review (≥2 approvals,
   `base=master`, all 39+ checks) — no special handling; mergify picks up the
   new rule the moment the PR merges into `master`.

## Tasks (atomic, independently committable)

- [x] T1: add the rule to `.mergify.yml` with `actions: comment` (message
      stating the rule would auto-merge). Commit message
      `ci(mergify): add observation rule for documentation bot PRs`.
      Done 2026-11-13 in oqa2 on branch
      `feature/145_oqa2_auto_merge_documentation_prs`, commit `489059822`.
      Gate deviation: `xt/45-make-update-deps.t` (part of
      `make test-checkstyle`) fails on any dirty tree, so the full
      `make test-checkstyle` (incl. `test-gitlint`) ran green on the
      committed clean tree; yamllint also passed pre-commit.
- [ ] T1b: PR #8107 opened against `os-autoinst:master`
      (https://github.com/os-autoinst/openQA/pull/8107). Needs 2 approvals
      via the normal flow; the rule is only active once merged into master.
- [x] T2: observe the next docs PR(s) opened by `os-autoinst-bot` against
      `gh-pages` (created daily ~04:44 UTC): the rule comment must appear and
      `statusCheckRollup` must show ≥4 successful checks. Record PR number +
      evidence in this plan. Observed on PR #8129 (comment posted by mergify,
      4 checks green).
- [x] T3: replace `actions: comment` with `merge: method: merge` in the same
      rule. Commit message `ci(mergify): auto-merge documentation bot PRs on gh-pages`.
      Implemented 2026-11-13 as commit `0d74a997a` (reuses the `*merge`
      anchor) on derived branch
      `feature/145_oqa2_auto_merge_documentation_prs_2` stacked on T1
      (`489059822`); full `make test-checkstyle` green. PR
      https://github.com/os-autoinst/openQA/pull/8110 merged into master
      on 2026-11-18.
- [x] T4: verify the first live auto-merge (`gh pr view <N> --repo
os-autoinst/openQA --json mergedAt,mergedBy` → merged by mergify[bot]);
      record in this plan; then move this plan file to `tasks/completed/` with
      plain `mv`. Verified live auto-merge on PR #8129: merged at
      2026-11-18T20:25:26Z by app/mergify. Plan complete.

## Risks / open questions

- Auto-merge trusts the bot's docs build (PR checks do not rebuild docs).
  Same trust model as the dependency-cron rule; accepted.
- If `gh-pages` gets branch protection with required checks later, the rule
  must be re-audited.
- Mergify merges only mergeable PRs; a conflicted docs PR is left unmerged
  and reported — no data-loss risk.

## Approvals

| Decision                                                                                                                     | Approver                                                                | Date       |
| ---------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ---------- |
| Auto-merge docs PRs via a dedicated mergify rule (design 1), scope `base=gh-pages` + `author=os-autoinst-bot` + title prefix | okurz (plan requester; recorded here, re-confirm at start of execution) | 2026-11-13 |
| Check threshold `#check-success>=4` + `#check-pending=0` instead of the `*core_checks` anchors                               | okurz (recorded, re-confirm)                                            | 2026-11-13 |
| `method: merge` (not squash) for `gh-pages`                                                                                  | okurz (recorded, re-confirm)                                            | 2026-11-13 |
| Staged rollout comment-only → merge (design 2), gated on one live observed docs PR                                           | okurz (recorded, re-confirm)                                            | 2026-11-13 |

## Gates

- T1 commit: `make test-checkstyle` (yamllint over `.mergify.yml`), then
  `make test-gitlint` after the commit exists.
- T2 observation gate:
  `gh pr view <N> --repo os-autoinst/openQA --json statusCheckRollup,comments`
  → 4+ successful external checks and the rule comment present.
- T3 commit: same as T1 (`make test-checkstyle` pre-commit,
  `make test-gitlint` post-commit).
- T4 verification gate: `gh pr view <N> --repo os-autoinst/openQA --json
mergedAt,mergedBy` → `mergedBy` is `mergify[bot]`, `mergedAt` non-null.

## Session starter

```
Read tasks/193_oqa2_auto_merge_documentation_prs.md fully (and tasks/todo.md),
load the git-workflow skill before any commit and the testing skill for the
gates. Work in the oqa2 working copy (/home/okurz/local/os-autoinst/oqa2),
branch off master, implement T1 only (mergify rule in .mergify.yml with
comment-only action), gate with make test-checkstyle, commit with the message
from the plan, gate with make test-gitlint. Actions needing explicit user
confirmation before running: pushing the branch to the okurz remote and
opening the PR against os-autoinst/openQA (mergify change takes effect
repo-wide as soon as the PR merges into master), and any action on
os-autoinst/openQA that enables auto-merging (T3).
```
