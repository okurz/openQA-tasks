# 155 oqa1: Consolidate pre-worktree deep-copy checkouts into a git-worktree workflow

Context: Local development checkout hygiene for openQA; retiring the deep-copy
working copies `oqa2`–`oqa5` in favour of git worktrees off the primary checkout.
Ticket: oqa1 (no Redmine ticket; scope is local development infrastructure)
Branch: `feature/155_oqa1_consolidate_worktree_workflow` (branched from `origin/master`)
Numbering: Prefix `155` as the next free sequential task number.

Aliases as of this plan: `oqa1` = primary checkout `~/local/os-autoinst/openQA`
(NOT a host alias). `oqa2`–`oqa5` = deep copies with their own `.git` directory.
`oqa-154-cleanup` = first worktree, created 2026-11-20.

---

## Problem Statement

The pre-worktree workflow kept four full clones of openQA side by side. Each has
its own object store, refs, remotes, `node_modules` and ignored build state, so
they drift apart instead of sharing one history:

1. **Duplicated storage and fetch traffic**: `du -sh` on 2026-11-20 reports
   `oqa2` 390M, `oqa3` 475M, `oqa4` 333M, `oqa5` 314M (~1.5G) against a single
   primary checkout, plus 4x `node_modules`.
2. **Refs that exist nowhere else**: 38 branches across the four clones have tips
   whose objects are absent from `oqa1`, and 181 remote-tracking refs (e.g.
   `okurz-local/pr-*`, `origin-local/*`) are likewise absent. Deleting a clone
   without a rescue step loses commits.
3. **Divergent remotes**: `oqa2` has `okurz,okurz-local,origin`; `oqa3` has
   `okurz,origin,origin-local`; `oqa4`/`oqa5` have `okurz,origin`. The same
   branch name means different things depending on the directory.
4. **Nested/stale worktree**: `oqa4` registers a prunable worktree
   `/tmp/oqa4-master` (path gone), so `oqa4` is itself a worktree host while
   being a deep copy.
5. **Discoverability**: `git worktree list` in `oqa1` shows unrelated temporary
   worktrees under `/tmp`, and `oqa2`–`oqa5` are invisible to it, so nobody can
   tell which checkouts are live.

Measured inventory (2026-11-20, `git -C <dir>` queries only):

| Dir  | Kind       | HEAD branch                                                           | Refs absent from `oqa1` (heads/remotes) | Dirty                                     | Size |
| :--- | :--------- | :-------------------------------------------------------------------- | :-------------------------------------- | :---------------------------------------- | :--- |
| oqa2 | deep clone | `feature/119_poo203865_support_repo_asset_download_1`                 | 18 / 131                                | clean                                     | 390M |
| oqa3 | deep clone | `feature/062_poo198851_ensure_cache_mkdir_p`                          | 10 / 30                                 | 65 untracked (`public/dist`, regenerable) | 475M |
| oqa4 | deep clone | `feature/140_oqa4_poo207879_api_key_handling` (+7 vs `origin/master`) | 3 / 8                                   | clean                                     | 333M |
| oqa5 | deep clone | `feature/032_oqa5_ssh_key_auth_packaging_1`                           | 7 / 12                                  | clean                                     | 314M |

`oqa1` remotes are already the desired pair: `origin` =
`git@github.com:os-autoinst/openQA.git`, `okurz` =
`git@github.com:okurz/openQA.git`. `oqa1` currently registers 5 worktrees
(`oqa1` itself, an os-autoinst-common subrepo worktree, `oqa-154-cleanup`,
`/tmp/opencode/pr8114`, `/tmp/opencode/pr8114-base`).

---

## Target Architecture

```
~/local/os-autoinst/
├── openQA/                 <- oqa1: the ONE object store, primary checkout
│   └── .git/worktrees/     <- worktree admin data
├── oqa-154-cleanup/        <- git worktree (branch feature/154_...)
├── oqa-140-api-key/        <- git worktree (rescued from oqa4)
├── archive/                <- git bundles + moved clone dirs (retention)
│   ├── oqa2-20261120.bundle
│   └── oqa2/               <- moved, not deleted; removal after approval
└── (no more deep clones)
```

Rules this plan establishes:

- All work happens in `oqa1` or in a worktree registered against it.
- Worktree directory naming: `oqa-<NNN>-<slug>` sibling of `oqa1`
  (`oqa1` itself keeps its name and remains the alias for the primary checkout).
- `node_modules` is shared into a worktree by symlink to `oqa1/node_modules`
  when only lint/style/tests are needed (validated with `oqa-154-cleanup`), or
  installed locally when the worktree must diverge.
- Clone heads are adopted as `refs/remotes/clones/<name>/*` in `oqa1`, i.e. the
  rescue direction is clone -> primary, never primary -> GitHub, so no remote
  writes happen during consolidation.

Alternatives considered and rejected:

- **Keep the clones** — keeps diverging remotes, invisible refs and 4x storage.
- **Convert `oqa1` to a bare repo plus worktrees** — cleaner in theory, but
  breaks the long-standing `~/local/os-autoinst/openQA` working-copy habit and
  buys nothing over "primary + worktrees".
- **`git clone --shared` / `--reference` clones** — still separate admin dirs
  and refs; worktrees already give the same object sharing with less machinery.

---

## Preconditions

Before any execution step:

- `git -C ~/local/os-autoinst/openQA status --porcelain` is checked first. If
  the primary checkout has uncommitted or staged work, create the plan's
  worktree instead of committing from the primary checkout:
  `git -C ~/local/os-autoinst/openQA worktree add ~/local/os-autoinst/oqa-155-worktree -b feature/155_oqa1_consolidate_worktree_workflow origin/master`
- No network operation is needed for any task below; all fetches are local-path
  fetches from clone to `oqa1`.
- `tasks/` is excluded via `.git/info/exclude:37`, so this plan file and any
  local artifacts under `tasks/` are never staged.

---

## Detailed Task Breakdown

### Task 1 (Commit 1): Add `script/openqa-worktree-audit` with tests

- **Files**:
  - `script/openqa-worktree-audit` (new, executable)
  - `t/44-scripts-openqa-worktree-audit.t` (new)
- **Objective**:
  - Read-only auditor over a primary checkout plus candidate directories (deep
    clones or worktrees). For each path report:
    - `kind`: `primary`, `worktree` (`.git` file), `clone` (`.git` directory),
      or `missing`
    - `head`: current branch or `detached`
    - `upstream`, `ahead`/`behind`
    - `dirty`: staged/modified/untracked counts, `stashes`
    - `heads_at_risk`: local branches whose tip object is absent from the
      primary (`git cat-file -e`); this is the decommission gate
    - `remote_refs_at_risk`: same for `refs/remotes/*`
  - Interface:
    `script/openqa-worktree-audit [--primary PATH] [--base REF] [--json] PATH...`
    with `--primary` defaulting to the repo containing the script,
    `--base` defaulting to `origin/master`.
  - Exit non-zero when any directory reports at-risk refs, so it can gate
    Task 3 and Task 5 mechanically.
  - Keep it dependency-free (core Perl, `Mojo::File`, `IPC::Open3` via
    `OpenQA::Utils::run_cmd`/`run_cmd_with_output` if already used by scripts;
    prefer existing helpers over shelling out with backticks).
- **Tests** (`t/44-scripts-openqa-worktree-audit.t`):
  - `git init` two fixture repos in a tempdir: a "primary" and a "clone" whose
    branch carries one commit the primary does not have; assert
    `heads_at_risk == 1` and exit code 1.
  - Fetch the clone into the primary as `refs/remotes/clones/fixture/*`; assert
    `heads_at_risk == 0` and exit code 0 (this is exactly the Task 3 gate).
  - Assert JSON shape is stable for a clean worktree fixture and for a missing
    path (reported, not fatal).
  - Assert a dirty fixture repo reports non-zero `modified` count.
- **Verification**: see Gates, Commit 1.

### Task 2 (Commit 2): Document the worktree workflow for developers

- **Files**:
  - `docs/Contributing.md` (developer setup section)
- **Objective**:
  - Document the canonical layout (`oqa1` primary + `oqa-<NNN>-<slug>`
    worktrees), why deep copies are retired, and the operational rules:
    - creating: `git -C ~/local/os-autoinst/openQA worktree add ~/local/os-autoinst/oqa-<slug> -b <branch> origin/master`
    - listing/pruning: `git worktree list`, `git worktree prune`
    - sharing `node_modules` by symlink for lint/test-only worktrees
    - removing: `git worktree remove <path>` only after the branch is pushed or
      adopted, never `rm -rf`
    - the "one object store, many checkouts" model and that PR branches are
      fetched into `oqa1` rather than cloned again
  - Reference `script/openqa-worktree-audit` as the pre-deletion check.
- **Verification**: see Gates, Commit 2.

### Task 3 (Operational, no commit): Snapshot and adopt clone refs into `oqa1`

- **Objective**: make every clone ref reachable from `oqa1` and keep a
  complete, verifiable snapshot before any directory is moved.
- **Steps** (per clone `N` in `oqa2 oqa3 oqa4 oqa5`):
  1. Snapshot all refs and objects:
     `mkdir -p ~/local/os-autoinst/archive`
     `git -C ~/local/os-autoinst/N bundle create ~/local/os-autoinst/archive/N-20261120.bundle --all`
     `git -C ~/local/os-autoinst/N bundle verify ~/local/os-autoinst/archive/N-20261120.bundle`
  2. Adopt heads (local-path fetch, no network):
     `git -C ~/local/os-autoinst/openQA fetch --no-tags ~/local/os-autoinst/N '+refs/heads/*:refs/remotes/clones/N/*'`
  3. Adopt the non-standard remote-tracking namespaces so nothing is stranded:
     `git -C ~/local/os-autoinst/openQA fetch --no-tags ~/local/os-autoinst/N '+refs/remotes/okurz-local/*:refs/remotes/clones/N/okurz-local/*' '+refs/remotes/origin-local/*:refs/remotes/clones/N/origin-local/*'`
     (only the namespaces that exist in that clone; check with
     `git -C ~/local/os-autoinst/N remote`)
  4. Gate: `script/openqa-worktree-audit --primary ~/local/os-autoinst/openQA oqa2 oqa3 oqa4 oqa5`
     from `~/local/os-autoinst` must exit 0 and report `heads_at_risk: 0` for all
     four directories.
- **Verification**: see Gates, Task 3 row.

### Task 4 (Operational, no commit): Recreate active branches as worktrees

- **Objective**: continue the branches that are still being worked on, as
  worktrees, and drop stale worktree registrations before archiving.
- **Steps**:
  1. Prune the dead registration inside the clone:
     `git -C ~/local/os-autoinst/oqa4 worktree prune` and confirm
     `git -C ~/local/os-autoinst/oqa4 worktree list` shows only `oqa4` itself.
  2. Recreate each branch that must stay live in `oqa1` from the adopted ref,
     then attach a worktree. Minimum set identified on 2026-11-20 (confirm with
     the owner before creating):
     - `feature/140_oqa4_poo207879_api_key_handling` (oqa4, +7 vs master)
     - `feature/143_poo209874_avoid_duplicate_key_bugs_bugid` (oqa2)
     - `feature/032_oqa5_ssh_key_auth_packaging_1` (oqa5)
     - `feature/119_poo203865_support_repo_asset_download_1` (oqa2)
     ```bash
     git -C ~/local/os-autoinst/openQA branch <branch> refs/remotes/clones/<N>/<branch>
     git -C ~/local/os-autoinst/openQA worktree add ~/local/os-autoinst/oqa-<NNN>-<slug> <branch>
     ln -s ~/local/os-autoinst/openQA/node_modules ~/local/os-autoinst/oqa-<NNN>-<slug>/node_modules
     ```
  3. Everything else stays as `refs/remotes/clones/<N>/*` in `oqa1`; no
     worktree is created for it (recoverable with `git branch <b> clones/<N>/<b>`
     at any time).
  4. Verify each new worktree builds its test tooling:
     `make -C ~/local/os-autoinst/oqa-<NNN>-<slug> tidy`.
- **Verification**: see Gates, Task 4 row.

### Task 5 (Operational, no commit): Archive the deep copies, defer deletion

- **Objective**: remove the clones from the working path without destroying
  data, and reclaim the space only after a cooling-off period.
- **Steps**:
  1. Move, never delete:
     `mkdir -p ~/local/os-autoinst/archive`
     `mv ~/local/os-autoinst/oqa2 ~/local/os-autoinst/archive/oqa2-20261120`
     (same for `oqa3`, `oqa4`, `oqa5`)
  2. Verify `oqa1` is unaffected and the archive is intact:
     `git -C ~/local/os-autoinst/openQA worktree list`,
     `git -C ~/local/os-autoinst/openQA fsck --connectivity-only`,
     `ls -l ~/local/os-autoinst/archive/*.bundle`
  3. Record the space reclamation after moving:
     `du -sh ~/local/os-autoinst/archive ~/local/os-autoinst/openQA`
  4. Deletion of `archive/oqa*-20261120` happens only after >= 30 days
     (not before 2026-12-20) and only with explicit user confirmation. Until
     then the bundles are the authoritative fallback.
- **Verification**: see Gates, Task 5 row.

### Task 6 (Operational, local-only, no commit): Update local plan documents

- **Objective**: stop the retired aliases from reappearing in future plans.
- **Steps**:
  1. `grep -rn 'oqa[2-5]' ~/local/os-autoinst/openQA/tasks/` and rewrite
     references to "worktree `oqa-<NNN>-<slug>`" where they mean a checkout.
     `tasks/` is excluded from git, so this is a local edit only.
  2. Store the audit output next to the plans for future reference:
     `script/openqa-worktree-audit --json ... > ~/local/os-autoinst/openQA/local/oqa-worktree-audit-20261120.json`
     (or `tasks/` if `local/` is not present).
- **Verification**: see Gates, Task 6 row.

---

## Approvals

| Decision                                                                                                                                        | Approver | Date    |
| :---------------------------------------------------------------------------------------------------------------------------------------------- | :------- | :------ |
| Canonical model: `~/local/os-autoinst/openQA` (= `oqa1`) is the single object store; all other checkouts are worktrees named `oqa-<NNN>-<slug>` | pending  | pending |
| Rescue direction clone -> `oqa1` via `refs/remotes/clones/<name>/*`; no pushes to GitHub during consolidation                                   | pending  | pending |
| Create a `git bundle --all` snapshot of every clone before moving any directory                                                                 | pending  | pending |
| Clones are moved to `~/local/os-autoinst/archive/`, never deleted; removal only after 30 days plus explicit confirmation                        | pending  | pending |
| New `script/openqa-worktree-audit` with JSON output and non-zero exit on at-risk refs, shipped with tests                                       | pending  | pending |
| Prune the stale `/tmp/oqa4-master` registration instead of recreating it                                                                        | pending  | pending |
| Worktree list to keep live after consolidation (branch names in Task 4)                                                                         | pending  | pending |

---

## Gates

| Commit             | Scope                                                                      | Verification Command                                                                                                                                                                                                                                                                                                |
| :----------------- | :------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Commit 1           | `script/openqa-worktree-audit` plus `t/44-scripts-openqa-worktree-audit.t` | `make tidy && make test-checkstyle && COVERAGE=1 make test-unit-and-integration TESTS=t/44-scripts-openqa-worktree-audit.t && make check-line-coverage && make test-gitlint`                                                                                                                                        |
| Commit 2           | `docs/Contributing.md` worktree workflow section                           | `make test-markdown && SKIP_UPDATE_DEPS=1 make test-checkstyle && make test-gitlint`                                                                                                                                                                                                                                |
| Task 3 (no commit) | Bundle snapshot + adoption of clone refs                                   | `for N in oqa2 oqa3 oqa4 oqa5; do git -C ~/local/os-autoinst/$N bundle verify ~/local/os-autoinst/archive/$N-20261120.bundle; done && cd ~/local/os-autoinst && ~/local/os-autoinst/openQA/script/openqa-worktree-audit --primary ~/local/os-autoinst/openQA oqa2 oqa3 oqa4 oqa5` (must exit 0, `heads_at_risk: 0`) |
| Task 4 (no commit) | Stale worktree pruned + active branches recreated as worktrees             | `git -C ~/local/os-autoinst/openQA worktree list && for w in ~/local/os-autoinst/oqa-*-*/; do make -C "$w" tidy; done`                                                                                                                                                                                              |
| Task 5 (no commit) | Clones moved to archive                                                    | `git -C ~/local/os-autoinst/openQA fsck --connectivity-only && git -C ~/local/os-autoinst/openQA worktree list && ls -l ~/local/os-autoinst/archive/*.bundle && du -sh ~/local/os-autoinst/archive`                                                                                                                 |
| Task 6 (no commit) | Local plan documents updated                                               | `grep -rn 'oqa[2-5]' ~/local/os-autoinst/openQA/tasks/ \|\| echo "no stale alias references"`                                                                                                                                                                                                                       |

---

## Session starter

```markdown
Continue with execution plan `tasks/155_oqa1_consolidate_worktree_workflow.md`.
Load skills: `git-workflow`, `perl-dev`, `testing`.
Branch: `feature/155_oqa1_consolidate_worktree_workflow` based on `origin/master`.
Because `~/local/os-autoinst/openQA` is dirty, execute in a fresh worktree:
`git -C ~/local/os-autoinst/openQA worktree add ~/local/os-autoinst/oqa-155-worktree -b feature/155_oqa1_consolidate_worktree_workflow origin/master`
Commit unit: Start with Task 1 (`script/openqa-worktree-audit` plus `t/44-scripts-openqa-worktree-audit.t`), then Task 2 (docs).
Confirm with the user before: (a) fetching clone refs into `oqa1`, (b) creating
or removing worktrees, (c) moving `oqa2`–`oqa5` into
`~/local/os-autoinst/archive/`, and (d) any deletion. Never delete a clone
directory; never push.
```
