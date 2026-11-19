# 147: make `/review-as-bot` reliable for non-interactive runs

Surface: agent tooling only — `~/.config/opencode` (own git repo, `main` ahead 14) and the openQA
review checklist. No openQA product code, no Redmine ticket.

## Evidence (2026-11-18)

Three `pi -p` sessions, model `helmcode/deepseek-v4-flash`, one PR each, no review threads on the PR:

| PR | Verdict | Outcome |
|---|---|---|
| #7915 `_DROP_SETTINGS` | APPROVED | mergify merged, 2 min |
| #8110 mergify docs auto-merge | APPROVED | mergify merged, 2 min |
| #8085 Typer stale-user CLI | CHANGES_REQUESTED | open; 4 blocking findings, all 4 re-verified by hand as real |

Verdict quality is not the problem. The run exposed five tooling defects:

1. **Write gate had to be smuggled in.** `commands/review-as-bot.md` step 5 requires user confirmation
   before posting. Non-interactive use only worked by appending "…the write gate is waived…" to
   `$ARGUMENTS`, which the command also uses as the PR selector.
2. **`gh-as-bot` rule is prose, not enforced.** One session reported "verified via `gh api user`" —
   the human token. Nothing caught it; only the global `AGENTS.md` avoided a review attributed to
   `okurz` instead of `os-autoinst-review`.
3. **No isolation rule.** Sessions extracted PR heads and ran `prove`/`pytest` inside the openQA
   checkout. `git status` was clean afterwards by luck, not by design.
4. **Facts restated from memory.** #7915's body said "anubhav-agarwal/aylen384 approval"; the only
   approver was `aylen384`.
5. **Repo-specific traps rediscovered per run.** #8085 needed 3 min to find that a new `tests/`
   directory is executed by nothing (the Makefile only runs `ruff`), and that unit files sit in
   `%files` while the script is behind `%if %{with python_scripts}`.

## Target files

| Path | Repo | Role |
|---|---|---|
| `~/.config/opencode/commands/review-as-bot.md` | `~/.config/opencode` | the command; mirrored into pi via `~/.pi/agent/prompts -> ~/.config/opencode/commands` |
| `~/.config/opencode/review-checklist.md` | `~/.config/opencode` | one-line-question checklist read by `review-protocol.md` |

Out of scope: `~/.agents/skills/openqa/SKILL.md` (untracked in the `$HOME` repo, and
`~/.config/opencode/skills/openqa` vanished mid-session — no volatile path in this plan unless
approved as D2); `agents/deepseek-reviewer.md`; the model choice; GitLab paths.

## Tasks

Each task is one commit in `~/.config/opencode`, Conventional Commits, body wrapped at 80.

### Task 1: first-class non-interactive mode
Files: `commands/review-as-bot.md`.
- [ ] Frontmatter `argument-hint: "<pr|url> [--post] [--dry-run]"`.
- [ ] New step: `--post` or `REVIEW_BOT_POST=1` skips the step-5 confirmation gate and posts
      immediately; `--dry-run` prints the draft body and posts nothing.
- [ ] "No human is watching: never end a run without either a submitted review or a printed error and
      non-zero exit."
- [ ] The PR selector reads only the first non-flag argument, so trailing prose is no longer needed.
- Commit: `feat(review): add explicit --post and --dry-run modes`

### Task 2: enforce bot identity
Files: `commands/review-as-bot.md`.
- [ ] "Every GitHub call in this workflow must use `gh-as-bot`; bare `gh` posts as the human account."
- [ ] Post-condition: `gh-as-bot api repos/<o>/<r>/pulls/<n>/reviews --jq '.[-1].user.login'` must
      equal `os-autoinst-review`, otherwise report the attribution failure instead of success.
- Commit: `fix(review): require gh-as-bot and verify review attribution`

### Task 3: worktree isolation
Files: `commands/review-as-bot.md`.
- [ ] Inspect and test in `git worktree add --detach /tmp/review-<pr> <head-sha>`; "never modify the
      working tree of the checkout you start in"; remove the worktree at the end.
- Commit: `fix(review): isolate inspection in a detached worktree`

### Task 4: verdict discipline
Files: `commands/review-as-bot.md`.
- [ ] Any finding that asks for an edit, however small, is `REQUEST_CHANGES`. `Nit:` inside an
      `APPROVE` is not usable: mergify merges on approvals and does not inspect unresolved threads, so
      those items get dropped (evidence: #8110 merged 2 min after the bot's approval and its
      `merge-skip` brake nit is still absent from `.mergify.yml` on master).
- [ ] A finding blocks only when it is valid: it names `file:line`, cites the rule or the failure mode
      it violates (repo `AGENTS.md`, `review-checklist.md`, or a concrete broken behavior), and proposes
      a concrete edit. Open questions and preferences stay in the body without affecting the verdict.
- [ ] A point a human already answered or dismissed in a reply on the same commit is not re-raised.
- [ ] Verdict is keyed to what the bot already said on this commit: if the bot requested changes on this
      head sha and its own blocking threads are still unresolved, keep that verdict and only add what the
      earlier review missed. It must not flip to `APPROVE` on sampling luck; it must approve once the
      author resolved those threads, whether or not a new commit was pushed.
- [ ] The review body names the model that produced it, because several models are used.
- [ ] Blocking findings are posted as inline review comments anchored to the line, falling back to the
      body when the line is not in the diff; `--dry-run`/`--post` are documented as GitHub-only.
- [ ] Body separates "verified by execution" (command + result) from "read only".
- [ ] The review body names no model.
- [ ] Step 4 reads `~/.config/opencode/review-checklist.md` before deciding.
- Commit: `docs(review): block on any requested edit, keep verdicts sha-stable`

### Task 5: verbatim facts
Files: `commands/review-as-bot.md`.
- [ ] Approvals, requested reviewers, check counts and reviewer logins are quoted from
      `gh-as-bot pr view <n> --json reviews,reviewDecision,statusCheckRollup`, never paraphrased.
- Commit: `docs(review): quote review facts verbatim`

### Task 6: openQA review gates in the checklist
Files: `review-checklist.md` (new section, same one-line-question style).
- [ ] Is the failing check a stale-base OBS context (`OBS: openQA - openSUSE_Tumbleweed/x86_64`) that
      a rebase clears, rather than a real failure?
- [ ] Does the PR reach the mergify floor (2 approvals, `#check-success>=39`, `0` pending, no
      `acceptance-tests-needed`/`not-ready`/`merge-skip-*` label)?
- [ ] For new or changed Perl lines: was `COVERAGE=1` plus `make check-line-coverage` run?
- [ ] For new Python code: is the pytest file executed by a Makefile target or CI job (this repo only
      runs `ruff`), or is it dead weight?
- [ ] Do packaging conditionals agree — unit files in `%files` vs. the script behind
      `%if %{with python_scripts}`?
- [ ] Is the `poo#` bugref present and consistent with the change?
- Commit: `docs(review): add openQA-specific review gates`

### Task 7: live validation, two cycles (posting, needs D3)
- [ ] Cycle 1: `--post` on #8108 (own PR, two unresolved nit threads). Expect `REQUEST_CHANGES` with
      the suggestions anchored inline.
- [ ] Apply both of perlpunk's `qr{}` suggestions, push, re-run `--post`. Expect `APPROVE` and a mergify
      merge: that is the only full end-to-end proof that a blocking nit can be lifted again.
- [ ] Optional: same on #7777 and a plain `--post` on #8085 (expect it to stay `REQUEST_CHANGES`).
- [ ] Record verdict, model, and review URL per run in `## Run log`.
- Commit: none in openQA; this plan file is updated with plain `edit`, never committed.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Review posted as `okurz` | High, irreversible | Task 2 attribution check before success is declared |
| Wrong-account or duplicate review on a merged PR | Low | Task 1 refuses to target merged/closed PRs |
| Test runs dirtying the openQA checkout | Medium | Task 3 worktree rule, gated by `git status --porcelain` |
| Single-slot LLM endpoint | Medium | run sessions sequentially, one per `bash` call, explicit `timeout` |
| Volatile dotfile paths | Medium | Tasks 1–6 touch only `~/.config/opencode` |

## Run log

| Date | Target | Model | Verdict | Review |
|---|---|---|---|---|
| 2026-11-18 | #7915 | deepseek-v4-flash | APPROVED, merged | `#pullrequestreview-5963887661` |
| 2026-11-18 | #8110 | deepseek-v4-flash | APPROVED, merged | `#pullrequestreview-5963910638` |
| 2026-11-18 | #8085 | deepseek-v4-flash | CHANGES_REQUESTED, 4 findings re-verified by hand | `#pullrequestreview-5963954111` |
| 2026-11-18 | #8108 (dry run) | deepseek-v4-flash | APPROVE with nits, nothing posted | — |
| 2026-11-18 | #8108 `6008a0c3` | deepseek-v4-flash | CHANGES_REQUESTED, inline nit on `$pr_args` | `#pullrequestreview-5965244755` |
| 2026-11-18 | #8108 `c341e9b5` | deepseek-v4-flash | APPROVED after fix and thread resolution | `#pullrequestreview-5965282130` |
| 2026-11-18 | #8108, #7777 (dry run, installed command) | deepseek-v4-flash | APPROVE / CHANGES_REQUESTED, nothing posted | — |

Implementation, `~/.config/opencode` on `main`, unpushed:

- `c88e0ea` feat(review): add explicit --post and --dry-run modes
- `ec0c929` fix(review): require gh-as-bot and verify review attribution
- `aebd8d8` fix(review): isolate inspection in a detached worktree
- `4f0dd36` docs(review): block on any requested edit, keep verdicts commit-stable
- `d0c8a40` docs(review): quote review facts verbatim
- `ad2d0e3` fix(review): refuse merged or closed targets (split out of Task 2 so each commit stays single-purpose)
- `a628b1d` docs(review): add openQA-specific review gates

## Approvals

| # | Decision | Approver | Date |
|---|---|---|---|
| D0 | Post bot reviews for #7915/#8110/#8085 non-interactively, verdict chosen by the model | okurz | 2026-11-18 |
| D1 | No model is pinned by the command; every run selects `--model`. The validation evidence in this plan was produced with `helmcode/deepseek-v4-flash`, and other models may be used for later runs | okurz | 2026-11-18 |
| D2 | Scope all edits to `~/.config/opencode`; leave `~/.agents/skills/openqa/SKILL.md` alone | okurz | 2026-11-18 |
| D3 | Live `--post` validation as the two-cycle test in Task 7 (#8108: block, then approve after the nit fix) | okurz | 2026-11-18 |
| D4 | Plan number `147` instead of the literal max-prefix result `406` (`feature/405_poo45671_…` is a ticket-derived branch prefix with no `tasks/405_*` file; `poo45671` is plan 136) | okurz | 2026-11-18 |
| D5 | Any requested edit, including a nit, yields `REQUEST_CHANGES`; verdicts are sha-stable so a re-review cannot loop | okurz | 2026-11-18 |
| D6 | A valid finding blocks regardless of severity; the bot may cost an extra amend/push cycle per PR, and its own taste is acceptable as long as the finding cites a rule or a broken behavior | okurz | 2026-11-18 |
| D7 | Apply the candidate to `~/.config/opencode/commands/review-as-bot.md` as six atomic commits; `--dry-run`/`--post` are GitHub-only; no model names in review bodies | okurz | 2026-11-18 |

Implementation may not start before D2 and D4 are recorded.

## Gates

Every commit, first:

```sh
git -C ~/.config/opencode diff --check
```

| Task | Verification command |
|---|---|
| 1 | `awk 'NR==1&&$0!="---"{exit 1} NR==2&&!/^description:/{exit 1}' ~/.config/opencode/commands/review-as-bot.md && grep -q -- '--dry-run' ~/.config/opencode/commands/review-as-bot.md && grep -q -- '--post' ~/.config/opencode/commands/review-as-bot.md` |
| 2 | `grep -q 'gh-as-bot api repos/.*pulls/.*reviews' ~/.config/opencode/commands/review-as-bot.md && ! grep -nE '(^|[^h])gh (pr|api)' ~/.config/opencode/commands/review-as-bot.md` |
| 3 | `grep -q 'worktree add --detach' ~/.config/opencode/commands/review-as-bot.md` |
| 4 | `grep -q 'review-checklist.md' ~/.config/opencode/commands/review-as-bot.md && grep -q 'file:line' ~/.config/opencode/commands/review-as-bot.md` |
| 5 | `grep -q 'json reviews,reviewDecision,statusCheckRollup' ~/.config/opencode/commands/review-as-bot.md` |
| 6 | `grep -c '^- ' ~/.config/opencode/review-checklist.md` increases by >= 6 versus `git -C ~/.config/opencode show HEAD:review-checklist.md` |

Behavioural gate after Tasks 1–5 (dry run must not post):

```sh
cd ~/local/os-autoinst/openQA
before=$(gh api repos/os-autoinst/openQA/pulls/8108/reviews --jq 'length')
timeout 900 pi -p -a --model helmcode/deepseek-v4-flash --name review-gate-8108 \
  '/review-as-bot https://github.com/os-autoinst/openQA/pull/8108 --dry-run' | tee /tmp/gate-8108.log
after=$(gh api repos/os-autoinst/openQA/pulls/8108/reviews --jq 'length')
[ "$before" = "$after" ] && grep -qE 'APPROVE|REQUEST_CHANGES' /tmp/gate-8108.log \
  && grep -q 'aylen384' /tmp/gate-8108.log \
  && [ -z "$(git status --porcelain)" ]
```

#8108 has exactly one approver (`aylen384`) and two open nit threads, so the same run checks the
verbatim-facts rule and the nit handling. Task 7 (posting) gate:

```sh
gh api repos/os-autoinst/openQA/pulls/8108/reviews \
  --jq '.[-1] | .user.login + " " + .state + " " + .html_url'
```

must print `os-autoinst-review APPROVED …` (or `CHANGES_REQUESTED` with `file:line` findings).

## Session starter

```text
Read ~/local/os-autoinst/openQA/tasks/147_improve_automated_review_bot.md in full and run
`git -C /home/okurz/local/os-autoinst/openQA status -sb` plus
`git -C /home/okurz/.config/opencode status -sb` before anything else.

Load skills: customize-opencode (editing my own opencode/pi command and checklist),
git-workflow (committing), openqa (repo review gates), testing (when a dry run executes tests).

Commit unit: one commit per task (Tasks 1–6) in /home/okurz/.config/opencode, Conventional
Commits, body wrapped at 80 columns, one paragraph of motivation only. Task 7 commits nothing;
it edits the plan's `## Run log` with `edit`.

Stop and ask me before: any `gh-as-bot pr review` that posts (D3), any commit or anything outside
/home/okurz/.config/opencode (D2), any push, and any renumbering of this plan (D4). Approvals
recorded in the plan are the only approvals.

Do Tasks 1–6 in order, running the per-task gate from `## Gates` after each edit, then the
behavioural dry run once after Task 5. Report per task: the commit hash, the gate command output
line, and any gate you had to weaken.
```
