# 156: Python coverage gate and type checks

Numbering: 156 is the next free sequential number (`tasks/` files currently
reach 155). The branch `feature/405_poo45671_improve_developer_mode_hint` is a
misnumbered outlier: it implements what is filed as
`completed/136_poo45671_improve_developer_mode_hint.md`, so its `405` prefix is
not a plan number and the max-prefix heuristic is not applied here.

## Base and preconditions

Base the work on `origin/master`: 156 is independent of the shell-only PR #8139
(`feature/146_210468_dump_db_tiered_retention`). Task 0 introduces the Python
test infrastructure, so the plan does not depend on any commit from #8139. If
#8139 is instead kept with its Python test-infrastructure commit, skip Task 0
and the two Makefile aggregate wiring lines in Task 4. No code change without
the approvals recorded below. No `git add`, `git commit` or `git rm` inside
`tasks/`.

## Context

There is no Python test runner wired into `make test` yet. `pyproject.toml`
already carries `[tool.coverage.report] fail_under = 100`, so the 100% gate
exists on paper only. The Python surface today is:

```
script/dump-db            (shell today; a Python rewrite is a separate follow-up)
script/openqa-label-all   (untested)
tools/check-markdown.py   (untested)
```

`tests/` and `tests/__init__.py` are created by Task 0.

Verified on 2026-11-20 (Tumbleweed, Python 3.13):

- `pytest --cov` without `source` counts the test modules too (`180` stmts);
  a `source` list is mandatory for meaningful numbers.
- `pytest --cov=script --cov=tools` reports 50%: `tools/check-markdown.py` is
  listed at 0% because `.py` files in `source` dirs are reported even when
  unexecuted; extensionless scripts are only measured when a test imports them.
- pytest-cov honours `fail_under = 100` from pyproject once `--cov` is passed.
- `ty check --python /usr/bin/python3 --python-version 3.12 <pyfiles>` reports
  exactly 2 diagnostics, both at `script/openqa-label-all:81`, caused by the
  module globals `openqa_cmd = ""` and `args = ""`.
- `vulture <pyfiles> --min-confidence 80` is clean.
- No version-agnostic `ty`/`vulture` RPM exists in Tumbleweed: `zypper se
  --match-exact ty`/`python3-vulture` find nothing. Verified again on
  2026-11-25: only the python-version-pinned `python313-ty` and
  `python313-vulture` exist.

Goal: add the Python test infrastructure, close the coverage holes first, then
make `make test`/`test-checkstyle` enforce 100% statement+branch coverage for
Python without per-author flags, then add type and dead-code checks that do not
break environments without the tools.

## Task 0: Add the Python test infrastructure

Commit: `build: add python test targets and dependencies`

Files: `Makefile`, `dependencies.yaml`, `dist/rpm/openQA.spec`,
`pyproject.toml`, `.gitignore`.

- `Makefile`: add `test-python-unit` (`python3 -m pytest $(PYTEST_ARGS)`) and
  `test-python: test-python-static-checks test-python-unit`, but do not wire
  them into `test`/`test-checkstyle-standalone` yet: there are no tests until
  Task 1 and bare `pytest` exits 5 when it collects none.
- `dependencies.yaml`: add `python3-pytest`, `python3-pytest-cov`,
  `python3-pytest-mock` to `test_requires`, then regenerate the spec macro with
  `make update-deps` instead of editing `%test_requires` by hand.
- `pyproject.toml`: add `pytest`, `pytest-cov`, `pytest-mock` to the dev group.
- `.gitignore`: add `.coverage` and `.pytest_cache/`.
- Acceptance: `make update-deps` is idempotent and `make test-python-static-checks`
  passes.

## Task 1: Cover `tools/check-markdown.py`

Commit: `test(python): cover tools/check-markdown.py`

Files: `tests/test_check_markdown.py` (new).

- Load the module with `SourceFileLoader` + `spec_from_loader` (the hyphenated
  filename prevents a normal import), mirroring `tests/test_dump_db.py`.
- Cover per function, using description strings only (no in-file comments):
  `_get_anchors_from_file`, `_get_markdown_links_from_file`,
  `_get_anchor_keys_from_markdown`, `_get_referenced_keys_from_markdown`.
- Cover every `_resolve_target_anchor_key` branch: `http(s)` target,
  target without `#`, `#anchor` (empty file part resolves to the source file),
  `other.md#anchor`.
- Cover the `check_anchors` CLI via `typer.testing.CliRunner`: missing
  directory (exit 1), unused anchor (exit 1), used anchor (exit 0) with
  `monkeypatch.chdir(tmp_path)` and a tiny `lib/x.pm` that references
  `file.md#anchor`.
- Cover the `if __name__ == "__main__"` block with
  `runpy.run_path(..., run_name="__main__")` and `typer.Typer.__call__` mocked.
- Acceptance: 100% statement and branch coverage for
  `tools/check-markdown.py`; no `omit`/`pragma: no cover` additions.

## Task 2: Cover `script/openqa-label-all` (keep the name)

Commit: `test(python): cover script/openqa-label-all`

Files: `tests/test_openqa_label_all.py` (new).

- Load via `SourceFileLoader` (extensionless script), as in Task 1.
- Cover: `_setup_parser` defaults; `_parse_args` verbosity mapping including the
  `args.verbose > len(verbose_to_log)` branch; `_call` with `dry_run` true and
  false plus return-code propagation (mock `subprocess.run`); `_openqa_call`;
  `_comments` (mock `subprocess.run` stdout as JSON); `_needs_label` true/false.
- Cover `_main`: no jobs (returns 61), jobs without the requested module (no
  calls), matching jobs with/without existing label, `--no-restart` true and
  false, and a host without the `https://` prefix (assert the URL passed to
  `requests.get`).
- Cover the `if __name__ == "__main__"` block via `runpy` with `_main` mocked.
- Acceptance: 100% statement and branch coverage for `script/openqa-label-all`;
  do not rename the script.

## Task 3: Require Python 3.12 and fix ty diagnostics

Commit: `build: require Python 3.12 and fix ty diagnostics`

Files: `pyproject.toml`, `script/openqa-label-all`.

- `requires-python = ">=3.12"` (decided: align with `../os-autoinst-scripts`;
  qem-bot uses `~=3.13.0`, the stricter alternative).
- Annotate the module globals so ty stops inferring `str`:
  `openqa_cmd: list[str] = []` and
  `args: argparse.Namespace = argparse.Namespace()`; `_main` keeps assigning
  both via `global`.
- No behaviour change; the tests from Tasks 1 and 2 must stay green.
- Acceptance: `ty check --python "$(python3 -c 'import sys; print(sys.prefix)')"`
  over `$(pyfiles)` exits 0; `pytest -q` passes; ruff clean.
- Note: `ty` is not an RPM in Tumbleweed, so this gate is developer-side until
  Task 5 optionally guards the tool.

## Task 4: Enforce Python coverage by default

Commit: `build: enforce python coverage in make test`

Files: `Makefile`, `pyproject.toml`.

- `pyproject.toml`: `[tool.coverage.run]` gains
  `source = ["script", "tools"]`; keep `branch = true` and the existing
  `fail_under = 100`. No `omit` entries and no `pragma: no cover`.
- `Makefile`: add `PYTEST_COVERAGE_ARGS ?= --cov --cov-report=term-missing`;
  `test-python-unit` runs `python3 -m pytest $(PYTEST_COVERAGE_ARGS) $(PYTEST_ARGS)`;
  add `test-python-unit-no-coverage` running `python3 -m pytest $(PYTEST_ARGS)`;
  keep `test-python: test-python-static-checks test-python-unit`.
- `Makefile` wiring (deferred from Task 0): add `test-python-unit` to the `test`
  prerequisites and switch `test-checkstyle-standalone` from
  `test-python-static-checks` to `test-python`, so CI's `checkstyle` job enforces
  the coverage gate.
- Do not emit `coverage.xml` in this plan (avoids `.gitignore`/codecov churn).
- Acceptance: `make test-python` reaches 100% with no extra flags;
  `make test-python-unit-no-coverage` passes; `make test-checkstyle` passes;
  `git status --porcelain` is empty afterwards.
- Consequence to state in the commit body: a new `.py` under `script/` or
  `tools/` without tests now fails the gate, and extensionless scripts are only
  measured once a test imports them.

## Task 5: Add type and dead-code checks (fatal)

Commit: `build: add python type and code-health checks`

Files: `Makefile`, `dependencies.yaml`, `dist/rpm/openQA.spec`.

Decision (2026-11-25): the checks are fatal, not skipped, and the tools are
declared dependencies of the devel package.

- `PYTHON ?= python3`
- `test-python-types`: `ty check --python "$$($(PYTHON) -c 'import sys; print(sys.prefix)')" $(pyfiles)`
- `test-python-code-health`: `vulture $(pyfiles) --min-confidence 80`
- Both fail when the tool is missing, with an install hint, following
  `test-shellcheck` (not `test-ruff`, which warns and skips).
- `test-python-static-checks: test-ruff test-python-conventions test-python-types test-python-code-health`
- `dependencies.yaml` `style_check_requires` gains `python3-ty` and
  `python3-vulture`, then `make update-deps` regenerates the spec.
- Resolution verified in the distribution metadata (2026-11-25): Tumbleweed's
  `python313-ty`/`python313-vulture` provide `python3-ty`/`python3-vulture`, and
  Leap 16.0 ships both packages under that name. `style_check_requires` only
  reaches `openQA-devel`/`openQA-no-selenium-devel`, which are not built below
  `suse_version` 1600, so Leap 15.6 builds (openQA, -common, -client, -worker)
  are unaffected.
- `pyfiles` must also match `*.py` by extension: `file --mime-type` reports
  `tests/test_check_markdown.py` as `text/html` because of the HTML anchors in
  its fixtures, which would silently drop it from ruff, ty and vulture.

## Deferred (not in this plan)

- `pytest-xdist` parallel execution and making xdist a declared dependency.
- `--cov-report=xml` plus `coverage.xml` gitignore and codecov wiring.
- Fatal (non-skipping) ty/vulture targets once the tools are packaged.

## Risks

- Task 4 raises the bar for every future Python file under `script/`/`tools/`;
  that is intended, but must be called out in the commit body so reviewers see
  the new gate.
- `requires-python >=3.12` is metadata only for RPM builds; openQA still builds
  for Leap 15.6 (Python 3.11). The script uses no 3.12-only syntax, so runtime
  is unaffected, but the declaration is a forward-looking choice shared with
  `../os-autoinst-scripts`.
- The fatal ty/vulture targets only work once the devel package rebuild carries
  the new `Requires`, so the CircleCI `checkstyle` job can be red between the
  merge and the `opensuse/openqa_ci` image refresh. Leap 16.0 builds the devel
  package and must keep shipping `python313-ty`/`python313-vulture`.
- `script/openqa-label-all` has module-level mutable globals; the Task 3
  annotations make ty pass without refactoring, so the tests in Task 2 must not
  depend on import-time state leaking between cases (reset `openqa_cmd`/`args`
  per test).

## Approvals

| Decision                                                                             | Approver             | Date       |
| ------------------------------------------------------------------------------------ | -------------------- | ---------- |
| Separate test commit for `tools/check-markdown.py` before the coverage gate          | okurz                | 2026-11-20 |
| Separate test commit for `script/openqa-label-all`, without renaming it              | okurz                | 2026-11-20 |
| Fix missing coverage first, enable the 100% gate afterwards                          | okurz                | 2026-11-20 |
| Align `requires-python` with qem-bot or `../os-autoinst-scripts`                     | okurz                | 2026-11-20 |
| Fix ty diagnostics and add ty checks accordingly                                     | okurz                | 2026-11-20 |
| Use `requires-python = ">=3.12"` (os-autoinst-scripts variant)                       | okurz                | 2026-11-25 |
| ty/vulture targets fail (not skip) and both tools become devel dependencies          | okurz                | 2026-11-25 |
| Leap 15.6 only needs openQA, -common, -client, -worker; the devel packages are excluded | okurz             | 2026-11-25 |
| No pytest-xdist and no coverage.xml in this plan                                     | pending confirmation | -          |
| 156 owns the generic Python test infrastructure; #8139 carries only the shell change | pending confirmation | -          |
| Python rewrite of dump-db as a separate follow-up PR after 156                       | pending confirmation | -          |
| Use sequential number 156 instead of the stray `405` branch prefix                   | okurz                | 2026-11-20 |

## Gates

Run from the openQA repo root, before each commit: `make tidy` and
`make test-python-static-checks`.

Task 0 commit:

```
make tidy
make update-deps
git diff --stat  # only Makefile, dependencies.yaml, dist/rpm/openQA.spec, pyproject.toml, .gitignore
make test-python-static-checks
git commit ...  # then:
make test-gitlint
make test-checkstyle
```

Task 1 commit:

```
pytest tests/test_check_markdown.py -q --cov=tools --cov-branch --cov-fail-under=100
pytest -q
git commit ...  # then:
make test-gitlint
```

Task 2 commit:

```
pytest tests/test_openqa_label_all.py -q --cov=script --cov-branch --cov-fail-under=100
pytest -q
git commit ...  # then:
make test-gitlint
```

Task 3 commit:

```
ty check --python "$(python3 -c 'import sys; print(sys.prefix)')" $(git ls-files | grep -v '\.md$' | xargs file --mime-type 2>/dev/null | grep -E 'text/x-script\.python|text/x-python' | grep --invert-match -E '^(t/data|container/openqa_data/)' | cut -d: -f1)
pytest -q
git commit ...  # then:
make test-gitlint
```

Task 4 commit:

```
make test-python
make test-python-unit-no-coverage
make test-checkstyle
git status --porcelain  # only the intended edits; no .coverage/.pytest_cache entries
git commit ...  # then:
make test-gitlint
```

Task 5 commit:

```
make test-python-static-checks
make test-python
make test-checkstyle
git commit ...  # then:
make test-gitlint
```

## Session starter

Exact prompt for the next session:

```
Execute tasks/156_python_coverage_and_type_checks.md (openQA repo) in order.
Load skills: python-dev, testing, git-workflow, openqa.
Base: origin/master (156 is independent of PR #8139). PR #8139 must contain
only the shell change; if it still contains the Python commits, stop and ask me
before rewriting that branch.
One commit per task, in the order given: Task 0 (python test infrastructure),
Task 1 (test check-markdown), Task 2 (test openqa-label-all), Task 3
(requires-python 3.12 + ty fixes), Task 4 (coverage gate + Makefile wiring),
Task 5 (guarded ty/vulture targets). Never combine two tasks in one commit.
Before starting Task 3, confirm with me: requires-python ">=3.12" vs "~=3.13.0",
and whether ty/vulture must be fatal or may skip when missing. Run the exact
per-task Gate commands, plus `make test-gitlint` after each commit, and report
the result of each gate. Do not `git add`/`git commit` anything inside tasks/;
only the openQA repo commits. Report the plan number used (156) and stop if a
gate fails; after Task 5 report readiness for the separate dump-db Python
rewrite follow-up PR instead of opening it.
```
