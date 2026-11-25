# 157: dump-db Python rewrite PR after 156

Blocked on: `tasks/156_python_coverage_and_type_checks.md`. Tasks 2 and later
must not start until the 156 PR is merged, because the rewrite relies on the
Python test infrastructure and the 100% coverage gate that 156 introduces.

## State as of 2026-11-20

The three-PR split is partially done already:

- `origin/master`: `1f7748a4d`
- PR #8139 (`feature/146_210468_dump_db_tiered_retention`, open) now contains
  exactly one commit: `e68ba7b41 feat: make openqa-dump-db atomic and add CLI
flags` (shell change plus `t/45-dump-db.t`). The remote `okurz/...` branch
  matches it.
- The preserved three-commit work is on local branch
  `feature/146_210468_dump_db_tiered_retention_2` at `94144e745`:
  - `e68ba7b41` shell change (also in #8139)
  - `e5fe5c8ee` `build: add python test targets and dependencies`
  - `94144e745` `refactor: rewrite dump-db in Python with Typer`
- Plan 156 is committed in `tasks/` but not implemented yet.
- `tasks/156` Task 0 recreates the infrastructure commit; after 156 is merged
  the rewrite PR must not re-add it.

## Task 1: Verify and pin the split state

No commit. Read-only git plus `gh` checks.

- Confirm PR #8139 has exactly the shell commit:
  `gh pr view 8139 --json commits -q '.commits[].oid'` returns one SHA equal to
  `e68ba7b41`.
- Confirm the preserved branch exists and holds the three commits:
  `git rev-parse --short feature/146_210468_dump_db_tiered_retention_2` is
  `94144e745` and `git log --oneline origin/master..<that branch>` lists three
  commits.
- If the branch is missing, recreate it from the still-present object:
  `git branch feature/146_210468_dump_db_tiered_retention_2 94144e745`.
- Do not push this branch; it is a local safety net only.

## Task 2: Rebuild the rewrite branch on top of 156 (blocked on 156)

Single commit on the openQA repo.

Precondition: the 156 PR is merged. Verify with
`git log origin/master --oneline | grep 'build: add python test targets'` and
`git show origin/master:Makefile | grep -n 'test-python-unit'`.

- `git fetch origin`, then
  `git checkout -b feature/dump_db_python_rewrite origin/master`.
- `git cherry-pick 94144e745` and resolve conflicts as follows:
  - `Makefile`: keep `origin/master` (156 already wires `test-python-unit` into
    `test` and `test-python` into `test-checkstyle-standalone`).
  - `pyproject.toml`: keep `origin/master`, then add only `"typer"` to
    `dependencies` (the pytest dev group and the `[tool.setuptools.packages.find]`
    exclude come from 156 Task 0).
  - `dist/rpm/openQA.spec`: keep both additions from the cherry-pick
    (`Requires: python3-base`, `Requires: python3-typer` in `%package local-db`
    and the `%prep` sed that rewrites both scripts).
  - `script/dump-db`, `tests/__init__.py`, `tests/test_dump_db.py`: take the
    cherry-pick versions; `t/45-dump-db.t` deletion comes with the cherry-pick
    and must be kept (the Perl test is replaced by the pytest suite).
- Amend only to fix the message if the cherry-pick changed it; the final commit
  subject must stay
  `refactor: rewrite dump-db in Python with Typer` with the existing rationale
  in the body.
- Do not include any 156 files (no Makefile/test-infra/requires-python changes
  of its own). The expected diff is: `script/dump-db`, `tests/test_dump_db.py`,
  `tests/__init__.py`, the `t/45-dump-db.t` deletion, `"typer"` in
  `pyproject.toml`, and the `dist/rpm/openQA.spec` local-db requires plus the
  `%prep` sed. No docs or `.gitignore` changes (both belong to the shell PR and
  156 Task 0).

## Task 3: Verify and open the rewrite PR (blocked on Task 2)

No new commit; push and PR only.

- Run the full gate on the branch (see `## Gates`).
- `git push -u okurz feature/dump_db_python_rewrite`
- `gh pr create --repo os-autoinst/openQA --head okurz:feature/dump_db_python_rewrite`
  with a body that states: replaces `t/45-dump-db.t` with
  `tests/test_dump_db.py`; the 100% Python coverage gate from 156 now covers
  `script/dump-db`; no `After:` needed because 156 is already merged.
- Related issue: https://progress.opensuse.org/issues/210468

## Task 4: Archive plan 146 after both PRs merge

Plain `mv` only; no `git add`/`git commit` inside `tasks/`.

- Once #8139 and the rewrite PR are merged:
  `mv tasks/review/146_210468_dump_db_tiered_retention.md tasks/completed/`
- Report the new path; the user stages/commits `tasks/` themselves.

## Risks

- Cherry-pick conflicts in `Makefile` and `pyproject.toml` are expected; resolving
  by "take the rewrite branch side" would duplicate 156's wiring and fail review.
- If 156 is not merged, `make test-python` on the rewrite branch will not enforce
  the gate and the rewrite could land with partial coverage. Do not start Task 2
  early.
- The preserved branch is local-only; if it is deleted before Task 2, recover
  `94144e745` from `git reflog` before garbage collection.

## Approvals

| Decision                                                                                                                | Approver             | Date       |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------- | ---------- |
| Split into shell-only PR #8139, plan 156 (Python infrastructure and gate), rewrite as a separate follow-up PR           | okurz                | 2026-11-20 |
| PR #8139 reduced to the shell commit and the three-commit state kept on `feature/146_210468_dump_db_tiered_retention_2` | okurz                | 2026-11-20 |
| The rewrite PR is blocked on 156 and must not start before 156 is merged                                                | okurz                | 2026-11-20 |
| Reuse the existing `refactor: rewrite dump-db in Python with Typer` commit message                                      | pending confirmation | -          |
| Conflict rule: keep 156's `Makefile`/`pyproject.toml`, re-add only typer/exclude and the spec local-db/sed changes      | pending confirmation | -          |
| Archive `tasks/review/146_210468_dump_db_tiered_retention.md` only after both PRs merge                                 | pending confirmation | -          |

## Gates

Task 1 (no commit):

```
gh pr view 8139 --repo os-autoinst/openQA --json commits -q '.commits[].oid'
git rev-parse --short feature/146_210468_dump_db_tiered_retention_2
git log --oneline origin/master..feature/146_210468_dump_db_tiered_retention_2
git status --porcelain
```

Expected: one PR commit (`e68ba7b41`), branch at `94144e745`, three commits
listed, clean openQA tree.

Task 2 commit:

```
git log origin/master --oneline | grep 'build: add python test targets'
git diff --stat origin/master
make tidy
make test-python
make test-python-unit PYTEST_ARGS="--cov=dump_db --cov-branch --cov-report=term-missing"
HEAVY=1 prove -l t/44-scripts.t
make test-checkstyle
git diff --stat origin/master  # script/dump-db, tests/, pyproject typer/exclude, spec local-db/sed, docs
git commit ...  # then:
make test-gitlint
git status --porcelain
```

Task 3 (no commit):

```
git push -u okurz feature/dump_db_python_rewrite
gh pr create --repo os-autoinst/openQA --head okurz:feature/dump_db_python_rewrite --title "refactor: rewrite dump-db in Python with Typer" --body-file <body>
gh pr view <new-number> --json commits -q '.commits[].messageHeadline'
gh pr checks <new-number>
```

Task 4 (no commit):

```
ls tasks/completed/146_210468_dump_db_tiered_retention.md
git -C tasks status --porcelain
```

## Session starter

Exact prompt for the next session:

```
Execute tasks/157_dump_db_python_rewrite_after_156.md (openQA repo). Load
skills: python-dev, testing, git-workflow, openqa.
Start with Task 1 (verify the split state) and report its gate output. Tasks 2
and later are BLOCKED on the 156 PR being merged: check
`git log origin/master --oneline | grep 'build: add python test targets'`; if
156 is not merged, stop after Task 1 and report that the plan is blocked.
Before Task 2's cherry-pick, confirm with me the conflict rule (keep 156's
Makefile/pyproject, re-add only typer/exclude plus the spec local-db/sed
changes) and the reuse of the existing rewrite commit message. Task 2 is a
single commit on feature/dump_db_python_rewrite; do not modify tasks/. Run the
exact gates for the task, including `make test-python` at 100% coverage and
`make test-gitlint`, and report each result. Ask for confirmation before
pushing and before opening the rewrite PR. Do not archive plan 146; only report
readiness for Task 4 after both PRs merge.
```
