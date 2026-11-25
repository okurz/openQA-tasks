# 155 oqa1: Consolidate pre-worktree deep-copy checkouts into a git-worktree workflow

Context: Local development checkout hygiene for openQA; retiring the deep-copy
working copies `oqa2`–`oqa5` in favour of git worktrees off the primary checkout.
Ticket: oqa1 (no Redmine ticket; scope is local development infrastructure)
Branch: none. The `feature/155_oqa1_consolidate_worktree_workflow` branch, its
worktree and its single `docs/Contributing.md` commit were removed on
2026-11-25 by owner decision; the commit is preserved as
`local/155-consolidate-worktree-workflow.patch` in the primary checkout.
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
`git@github.com:okurz/openQA.git`. Measured on 2026-11-20; `oqa5` has since
been fully adopted and its directory removed, while its refs and local branches
remain in `oqa1`. `oqa4` was adopted, branched and moved to
`archive/oqa4-20261120` on 2026-11-21; its refs and local branches remain in
`oqa1`.

`oqa1` currently registers 5 worktrees
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
├── archive/                <- moved clone dirs (retention, deletion deferred)
│   └── oqa2-20261120/      <- moved, not deleted; removal after approval
└── (no more deep clones)
```

Rules this plan establishes:

- All work happens in `oqa1` or in a worktree registered against it.
- Worktree directory naming: `oqa-<NNN>-<slug>` sibling of `oqa1`
  (`oqa1` itself keeps its name and remains the alias for the primary checkout).
- `node_modules` is installed inside each worktree (`make prepare-node-env`),
  not shared by symlink: a worktree may carry a different `package.json`, and a
  symlink would silently resolve the primary's tool versions. Duplicating the
  dependencies is accepted as the price of dependency isolation.
- The pre-deletion audit is the project-agnostic `git worktree-audit` in the
  `okurz/scripts` repository (`~/bin`), not a script in this repository.
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

- The plan is tracked in `~/local/os-autoinst/openQA/tasks/` and has no
  worktree of its own: the former
  `~/local/os-autoinst/oqa-155-consolidate-worktree-workflow` worktree and its
  branch were removed on 2026-11-25. Execute from the primary checkout
  `~/local/os-autoinst/openQA` or from any worktree; no commit is pending for
  this plan.
- The audit tool is `~/bin/git-worktree-audit` (invoked as
  `git worktree-audit`), shipped with pytest tests in `~/bin/test`; see Task 1.
- No network operation is needed for any task below; all fetches are local-path
  fetches from clone to `oqa1`.
- `tasks/` is excluded via `.git/info/exclude:37`, so this plan file and any
  local artifacts under `tasks/` are never staged.

---

## Detailed Task Breakdown

### Task 1 (Commit 1, moved out of this repository): Audit script

- **Done (2026-11-24)**: implemented as `git-worktree-audit` in the
  `okurz/scripts` repository (`~/bin`), where it is project-agnostic and covered
  by that repository's `make test`/`make checkstyle` (pytest, ruff, shellcheck,
  coverage). It was first committed here as
  `script/openqa-worktree-audit` plus `t/44-scripts-openqa-worktree-audit.t`; the
  branch was rebased to drop that commit, since the openQA tree has no use for
  a personal helper and the Python port needs no Perl tooling.
- **Interface** (unchanged from the original design, now Python):
  `git worktree-audit [--primary PATH] [--base REF] [--json] DIRECTORY...`,
  `--primary` defaulting to the current repository, `--base` to
  `origin/master`; exit 0 when nothing is at risk, 1 when any ref is at risk and
  2 on invalid usage. Per path it reports `kind` (`primary`/`worktree`/`clone`/
  `other`/`missing`), `head`, `upstream`, `ahead`/`behind`, `dirty` counts and
  `stashes`, plus `heads_at_risk` and `remote_refs_at_risk`.
- **Tests**: `~/bin/test/test_git_worktree_audit.py` covers the gate (branch tip
  absent from primary, then cleared after adopting into
  `refs/remotes/clones/…`), remote-tracking risk, worktree and missing-path
  reporting, dirty counts, detached HEAD, text output and the usage errors.
- **Verification**: `make test && make checkstyle` in `~/bin`; the tool
  reproduces the previous Perl output byte for byte on the archived `oqa4`.
- **Plan deviation**: originally Commit 1 of this branch; superseded by the
  owner decision to keep personal tooling out of the openQA tree.

### Task 2 (Commit 2): Document the worktree workflow for developers

- **Files**:
  - `docs/Contributing.md` (developer setup section)
- **Objective**:
  - Document the canonical layout (`oqa1` primary + `oqa-<NNN>-<slug>`
    worktrees), why deep copies are retired, and the operational rules:
    - creating: `git -C ~/local/os-autoinst/openQA worktree add ~/local/os-autoinst/oqa-<slug> -b <branch> origin/master`
    - listing/pruning: `git worktree list`, `git worktree prune`
    - installing dependencies per worktree (`make prepare-node-env`) instead of
      sharing `node_modules`, so a divergent `package.json` cannot silently
      resolve the primary checkout's tool versions
    - removing: `git worktree remove <path>` only after the branch is pushed or
      adopted, never `rm -rf`
    - the "one object store, many checkouts" model and that PR branches are
      fetched into `oqa1` rather than cloned again
  - Adopt the refs of a candidate checkout into the primary checkout
    (`git fetch --no-tags <path> '+refs/heads/*:refs/remotes/clones/<name>/*'`)
    as the pre-deletion check; the personal audit tool stays out of the
    repository.
- **Done (2026-11-24)**: committed as `docs/Contributing.md` on the 155
  branch. The dependency rule states that each worktree installs its own
  `node_modules` instead of symlinking the primary's. Gates `make test-markdown`,
  `make test-checkstyle-standalone` and `make test-gitlint` pass.
- **Dropped (2026-11-25)**: the branch, its worktree and this commit were
  removed by owner decision. The commit survives as
  `local/155-consolidate-worktree-workflow.patch` and can be reapplied with
  `git apply`; no PR was opened.
- **Verification**: see Gates, Commit 2.

### Task 3 (Operational, no commit): Snapshot and adopt clone refs into `oqa1`

- **Objective**: make every clone ref reachable from `oqa1` before any
  directory is moved. A `git bundle` snapshot is only taken when no filesystem
  backup exists.
- **Steps** (per clone `N` in `oqa2 oqa3`; `oqa5` and `oqa4` are adopted and
  no longer in the working path):
  1. Snapshot all refs and objects. Skipped by owner decision because a
     filesystem backup covers the clones and no bundle exists. Use this step
     only when no filesystem backup is available:
     `mkdir -p ~/local/os-autoinst/archive`
     `git -C ~/local/os-autoinst/N bundle create ~/local/os-autoinst/archive/N-20261120.bundle --all`
     `git -C ~/local/os-autoinst/N bundle verify ~/local/os-autoinst/archive/N-20261120.bundle`
  2. Adopt heads (local-path fetch, no network):
     `git -C ~/local/os-autoinst/openQA fetch --no-tags ~/local/os-autoinst/N '+refs/heads/*:refs/remotes/clones/N/*'`
  3. Adopt every remote-tracking namespace so nothing is stranded. Adopting
     only `okurz-local`/`origin-local` cannot reach the gate: the audit reports
     at-risk refs in `origin` (`oqa4` 7, `oqa2` 2) and `okurz` (`oqa2` 1,
     `oqa3` 10) as well:
     `git -C ~/local/os-autoinst/openQA fetch --no-tags ~/local/os-autoinst/N '+refs/remotes/*:refs/remotes/clones/N/*'`
  4. Gate from `~/local/os-autoinst`:
     `git worktree-audit --primary ~/local/os-autoinst/openQA oqa2 oqa3`
     must exit 0 with `heads_at_risk: 0` and `remote_refs_at_risk: 0` for all
     three directories.
- **Pilot done (2026-11-21)**: `oqa4` 6 heads and 288 remote refs adopted into
  `refs/remotes/clones/oqa4/*` (294 refs under that namespace in `oqa1`);
  the audit exits 0 with both at-risk counts 0. No bundle; filesystem backup.
- **Done (2026-11-25)**: `oqa3`'s 65 untracked `public/dist` files (3.6M
  regenerable build output) were removed before any adoption, so both remaining
  clones are clean and only carry refs.
- **Done (2026-11-25, `oqa2`+`oqa3`)**: 23 and 22 heads plus their whole remote
  namespaces adopted by local-path fetch, giving 717 refs under
  `refs/remotes/clones/oqa2/*` and 728 under `refs/remotes/clones/oqa3/*`
  (2013 refs under `clones/*` in total). The audit reports both at-risk counts
  0 and exits 0, also when pointed at the archived copies.
- **Verification**: see Gates, Task 3 row.

### Task 4 (Operational, no commit): Attach worktrees for the live branches

- **Objective**: continue the branches that are still being worked on as
  worktrees, and drop stale worktree registrations before archiving.
- **Steps**:
  1. Prune the dead registration inside the clone:
     `git -C ~/local/os-autoinst/oqa4 worktree prune` and confirm
     `git -C ~/local/os-autoinst/oqa4 worktree list` shows only `oqa4` itself.
  2. Confirm the live set with the owner before creating anything. Current
     candidates (2026-11-21):
     - `feature/140_oqa4_poo207879_api_key_handling` (oqa4 HEAD, +7 vs
       `origin/master`), using the local branch from Task 7
     - `feature/032_oqa5_ssh_key_auth_packaging_1` (already a local branch from
       the `oqa5` pilot)
     - Nothing else: `feature/143_poo209874_avoid_duplicate_key_bugs_bugid` and
       `feature/119_poo203865_support_repo_asset_download_1` already exist in
       `oqa1` and need no rescued worktree.
  3. Attach a worktree to the existing local branch (Task 7 created it; use
     `clones/<N>/<branch>` when it was namespaced):
     ```bash
     git -C ~/local/os-autoinst/openQA worktree add ~/local/os-autoinst/oqa-<NNN>-<slug> <branch>
     make -C ~/local/os-autoinst/oqa-<NNN>-<slug> prepare-node-env
     ```
  4. Branches not selected for a worktree stay ordinary local branches from
     Task 7; no worktree is required for them.
  5. Verify each new worktree builds its test tooling:
     `make -C ~/local/os-autoinst/oqa-<NNN>-<slug> tidy`.
- **Done (2026-11-21)**: `oqa4` pruned, the `/tmp/oqa4-master` registration is
  gone and `worktree list` in the clone shows the clone only. No worktree
  created for `feature/140_oqa4_poo207879_api_key_handling` per the deferred
  worktree decision; the local branch from Task 7 is sufficient.
- **Done (2026-11-25)**: `oqa2` and `oqa3` registered no worktrees at all, so
  `git worktree prune` was a no-op and no worktree was created for their
  branches either (deferred-worktree decision). `oqa1` now registers only
  `openQA`, the os-autoinst-common subrepo and the `oqa-<NNN>-<slug>` worktrees.
- **Verification**: see Gates, Task 4 row.

### Task 5 (Operational, no commit): Archive the deep copies, defer deletion

- **Objective**: remove the clones from the working path without destroying
  data, and reclaim the space only after a cooling-off period.
- **Steps**:
  1. Move, never delete:
     `mkdir -p ~/local/os-autoinst/archive`
     `mv ~/local/os-autoinst/oqa2 ~/local/os-autoinst/archive/oqa2-20261120`
     (same for `oqa3`; `oqa4` was moved on 2026-11-21, `oqa5` was already
     removed by the owner)
  2. Verify `oqa1` is unaffected and the archive is intact:
     `git -C ~/local/os-autoinst/openQA worktree list`,
     `git -C ~/local/os-autoinst/openQA fsck --connectivity-only`,
     `ls -ld ~/local/os-autoinst/archive/oqa*-20261120`
  3. Record the space reclamation after moving:
     `du -sh ~/local/os-autoinst/archive ~/local/os-autoinst/openQA`
  4. Deletion of `archive/oqa*-20261120` happens only after >= 30 days
     (not before 2026-12-20) and only with explicit user confirmation. Until
     then the filesystem backup of the moved directories is the only fallback.
- **Done (2026-11-21)**: `archive/oqa4-20261120` (332M). `fsck
  --connectivity-only` exits 0 (dangling commits only), `oqa1` worktree list
  unchanged, `du -sh archive` 646M including the owner's
  `archive/oqa5-use-worktrees`.
- **Done (2026-11-25)**: `archive/oqa2-20261120` (396M) and
  `archive/oqa3-20261120` (471M) moved. `fsck --connectivity-only` exits 0, the
  `oqa1` worktree list is unchanged, `du -sh archive` is 1.5G. No deep clone
  remains in the working path; every clone ref is reachable from `oqa1`.
- **Verification**: see Gates, Task 5 row.

### Task 6 (Operational, local-only, no commit): Update local plan documents

- **Objective**: stop the retired aliases from reappearing in future plans.
- **Steps**:
  1. `grep -rn 'oqa[2-5]' ~/local/os-autoinst/openQA/tasks/ | grep -v '/155_'`
     and rewrite references to "worktree `oqa-<NNN>-<slug>`" where they mean a
     checkout. Keep branch names such as `feature/032_oqa5_…` and the
     `wip/168_oqa5_…` file name, and do not rewrite this plan itself.
     `tasks/` is excluded from the outer repository, so this is a local edit
     only.
     Done (2026-11-21): `grep -rn 'oqa[2-5]' tasks/ | grep -v '/155_'` matches
     `oqa4` once, inside the copied `review/217_oqa4_poo207879_api_key_handling.md`,
     as a plan-file path, so nothing was rewritten.
     Done (2026-11-25): 10 matches over 4 files, all left as they are — branch
     names (`feature/poo209949_oqa2_large_mem_scheduling`,
     `feature/145_oqa2_auto_merge_documentation_prs`), the
     `193_oqa2_auto_merge_documentation_prs` file name and title, a stale
     intra-plan path in that completed plan, and
     `feature/032_oqa5_ssh_key_auth` (that line carried a stray `.md` suffix, a
     typo fixed 2026-11-25). No checkout alias instructs future
     work, and rewriting a completed plan would falsify its record.
  2. Store the audit output next to the plans for future reference:
     `git worktree-audit --json --primary ~/local/os-autoinst/openQA oqa2 oqa3 > ~/local/os-autoinst/openQA/local/oqa-worktree-audit-$(date +%Y%m%d).json`
     Done (2026-11-25): `local/oqa-worktree-audit-20261121.json` (oqa4) plus a
     fresh run after adoption.
- **Verification**: see Gates, Task 6 row.

### Task 7 (Operational, no commit): Preserve every clone head as a local branch

- **Objective**: make every clone branch usable directly for worktrees from
  `oqa1`, not only as `refs/remotes/clones/<N>/*`. All clones are done.
- **Steps** (after Task 3, before Task 5):
  1. For a clone head whose name is free in `oqa1` and whose tip is unique
     across the clones, create it directly:
     `git -C ~/local/os-autoinst/openQA branch <branch> refs/remotes/clones/<N>/<branch>`
  2. For a head whose name already exists in `oqa1` with a different tip, or
     whose name carries different tips in several clones, create a namespaced
     local branch and leave the existing `oqa1` branch untouched:
     `git -C ~/local/os-autoinst/openQA branch clones/<N>/<branch> refs/remotes/clones/<N>/<branch>`
  3. Skip a head whose tip equals the existing `oqa1` branch tip; it is already
     worktree-usable.
- **Split after the `oqa5` pilot (2026-11-21)**: 10 local branches exist (see
  below). Of the 62 clone head entries, the remaining `oqa2`-`oqa3` work is 41
  direct names and 9 namespaced entries
  (`clones/oqa2/{feature/119_…,feature/122_…,feature/143_…,feature/perlcritic_…,feature/subrepo_update,master}`,
  `clones/oqa3/{feature/100_…,feature/125_…_1,feature/125_…_2}`); no head in
  those two clones is skipped as identical.
- **Done (2026-11-25, `oqa2`+`oqa3`)**: 45 heads (oqa2 23, oqa3 22) → 36 direct
  and 9 namespaced
  (`clones/oqa2/{feature/119_…,feature/122_…,feature/143_…,feature/perlcritic_…,feature/subrepo_update,master}`,
  `clones/oqa3/{feature/100_…,feature/125_…_1,feature/125_…_2}`); no head was
  skipped as identical. `master` is namespaced on purpose even though `oqa1`
  has no local `master`: a clone tip must not claim the canonical name. The
  Task 7 gate prints nothing, also against the archived copies.
  Side effect to be aware of: the run that set upstreams for the new branches
  used the whole `okurz/*` remote namespace, so 28 pre-existing local branches
  that had no upstream and whose `okurz/<branch>` ref exists now track their
  fork ref as well; `local/branch-upstreams-okurz-20261125.txt` lists every
  branch that tracks `okurz/*` for review.
- **Done (2026-11-21)**: `oqa4` 6 local branches — 5 direct
  (`feature/138_poo167749_no_global_selenium_implicit_wait` with `_1` and `_2`,
  `feature/139_poo209604_show_worker_in_next_previous`,
  `feature/140_oqa4_poo207879_api_key_handling`) and `clones/oqa4/master`;
  every tip equals the clone head, no upstream set (no `okurz/*` ref for these
  names in `oqa1`).
- **Pilot done (2026-11-21)**: `oqa5` 10 local branches created (9 direct:
  `backup/8109-pre-restack`, `feature/032_oqa5_ssh_key_auth_{1,2,3,4}`,
  `feature/032_oqa5_ssh_key_auth_packaging_1`,
  `feature/144_poo210528_upgrade_cpu_llm_model`,
  `feature/test_detail_view_no_duplicated_command`,
  `stack/032_ssh_key_auth`; plus `clones/oqa5/master`); `feature/auto_update`
  skipped as identical. Upstreams set only for the two branches whose
  `okurz/*` ref exists in `oqa1`. Audit exits 0 after adopting 11 heads and
  263 remote refs.
- **Verification**: see Gates, Task 7 row.

### Task 8 (Operational, no commit): Merge clone plan files into `oqa1/tasks/`

- **Objective**: keep plans that exist only in a clone when the clone
  directories leave the working path. `tasks/` is a separate plans repository
  and is not part of any bundle.
- **Rules**: copy only (`cp -p`), preserve the `root`/`wip`/`review`/`completed`
  layout and keep the source file name unless it collides. A colliding incoming
  file is resolved by **renumbering it to the next free prefix** (owner decision
  2026-11-25), the same way the `oqa5` plans became `162`-`168`; never overwrite
  or merge an existing plan, never delete, and run no git operation inside
  `tasks/` (global constraint).
- **Steps**:
  1. Inventory and checksum the source tree (exclude nested `.git`).
  2. Assert every target path is free or its collision is resolved.
  3. Copy each file to the same relative path under
     `~/local/os-autoinst/openQA/tasks/`.
  4. Verify: `git -C ~/local/os-autoinst/openQA/tasks status --short` differs
     from the pre-copy baseline by exactly the copied paths and every checksum
     matches.
  5. Record the source file list and checksums under `local/` for the archive
     period.
- **Pilot done (2026-11-21)**: `oqa5` 7 files (5 root, 1 `review/`, 1 `wip/`),
  no path collisions, checksums verified. Renumbered on the owner's request
  because the source numbers collided with existing plans: `162` tested_repo,
  `163`-`166` proposals 1-4, `review/167` proposal 5,
  `wip/168_oqa5_ssh_key_auth_combined.md`. The only `oqa5` match inside them is
  the branch name `feature/032_oqa5_ssh_key_auth.md`.
- **Remaining**: none; every clone's plans are integrated.
- **Done (2026-11-25, `oqa2`+`oqa3`)**: 49 files copied with their layout
  (`oqa2` 28 incl. one PNG, `oqa3` 21 incl. six PNGs). 38 files carried a
  prefix already used in `tasks/` and were renumbered to `171`-`208`; `131`,
  `002`, `003`, `parallel_tests.md` and the screenshots kept their names. Six
  intra-plan references (`123`, `127`, `128`, `135`, `145`, `105`) were
  rewritten to the new numbers inside the copies. Mapping, including source
  checksums: `local/oqa2-oqa3-tasks-mapping-20261125.txt`. The target
  `git status --short` differs from the baseline by exactly the 49 added paths;
  no pre-existing plan was modified. Pre-existing duplicate prefixes in
  `tasks/` (`001`, `032`, `040`, `047`, `063`, `089`, `092`, `141`) are
  untouched; `139`/`140` became duplicates through the `oqa4` copy under the
  old keep-the-name rule and are left for an owner decision.
- **Done (2026-11-21)**: `oqa4` 3 files. `review/139_…` and `review/140_…`
  copied unchanged; the `review/138_poo167749_no_global_selenium_implicit_wait.md`
  collision was resolved by owner decision as a merge of the newer `oqa4` copy
  (script-timeout scaling note + `## Results` runtime table) into the existing
  plan file, no renumber, no overwrite, no deletion. Source list and checksums
  recorded in `local/oqa4-tasks-source-20261121.md5`; audit JSON in
  `local/oqa-worktree-audit-20261121.json`.
- **Verification**: see Gates, Task 8 row.

---

## Approvals

| Decision                                                                                                                                        | Approver | Date    |
| :---------------------------------------------------------------------------------------------------------------------------------------------- | :------- | :------ |
| Canonical model: `~/local/os-autoinst/openQA` (= `oqa1`) is the single object store; all other checkouts are worktrees named `oqa-<NNN>-<slug>` | okurz    | 2026-11-25 |
| Rescue direction clone -> `oqa1` via `refs/remotes/clones/<name>/*`; no pushes to GitHub during consolidation | okurz | 2026-11-21 |
| Create a `git bundle --all` snapshot of every clone before moving any directory | superseded | 2026-11-21 |
| Clones are moved to `~/local/os-autoinst/archive/`, never deleted; removal only after 30 days plus explicit confirmation                        | okurz    | 2026-11-25 |
| New `script/openqa-worktree-audit` with JSON output and non-zero exit on at-risk refs, shipped with tests | okurz | 2026-11-21 |
| Move the audit tool out of the openQA tree into `okurz/scripts` as Python `git-worktree-audit`; drop its commit from the 155 branch | okurz | 2026-11-24 |
| Install `node_modules` per worktree instead of symlinking the primary's, accepting the duplication for dependency isolation | okurz | 2026-11-24 |
| Extend `git delete-no-content-branches` to remove a worktree together with its no-content branch (`prune.worktrees`, default on) | okurz | 2026-11-24 |
| Prune the stale `/tmp/oqa4-master` registration instead of recreating it                                                                        | okurz    | 2026-11-25 |
| Worktree list to keep live after consolidation (branch names in Task 4)                                                                         | okurz    | 2026-11-25 |
| Every clone head becomes a local branch in `oqa1`; name collisions use `clones/<N>/<branch>` and never move an existing `oqa1` branch             | okurz    | 2026-11-25 |
| Pilot: `oqa5/tasks/` copied into `~/local/os-autoinst/openQA/tasks/` preserving layout, no deletions, no git operations in `tasks/`                 | okurz    | 2026-11-21 |
| `oqa2`-`oqa4` plan merge into `tasks/` with the same rules; the `review/138_…` collision needs an owner decision                                 | okurz    | 2026-11-25 |
| Filesystem backup replaces `git bundle` snapshots; no bundle is created before moving a clone                                                      | okurz    | 2026-11-21 |
| Pilot: `oqa5` refs adopted into `refs/remotes/clones/oqa5/*` (11 heads, 263 remote refs) and 10 local branches created (9 direct, `clones/oqa5/master`) | okurz    | 2026-11-21 |
| `oqa5` clone directory removed by the owner after its refs, local branches and plans were preserved in `oqa1`                                 | okurz    | 2026-11-21 |
| Worktree creation deferred; a local branch is enough until a worktree is needed                                                                   | okurz    | 2026-11-21 |
| Former `oqa5` plans renumbered to `162`-`168` to resolve prefix collisions with existing plans                                                      | okurz    | 2026-11-21 |
| `oqa4` in scope for this session: Tasks 3/4/7/8/5, refs adopted, branches created, plans merged, directory moved to `archive/oqa4-20261120`            | okurz    | 2026-11-21 |
| `oqa4` `review/138_…` collision resolved by merging the newer copy into the existing `oqa1` plan file, no renumber, no overwrite, no deletion          | okurz    | 2026-11-21 |
| From 2026-11-25 on, plan-file collisions are resolved by renumbering the incoming file to the next free prefix instead of merging                       | okurz    | 2026-11-25 |
| Untracked `public/dist` build output is deleted from clones before they are archived (`oqa3`, 65 files, 3.6M, removed 2026-11-25)                       | okurz    | 2026-11-25 |
| The 155 branch, its worktree and its docs commit are removed; the commit is kept as `local/155-consolidate-worktree-workflow.patch`                    | okurz    | 2026-11-25 |
| Post-checkout hook for worktree creation stays deferred until a worktree is next created                                                            | okurz    | 2026-11-25 |
| Delete `archive/oqa*-20261120` and `archive/oqa5-use-worktrees` not before 2026-12-20 and only with explicit confirmation                              | okurz    | 2026-11-25 |
| `oqa2` and `oqa3` fully consolidated on 2026-11-25: refs adopted, 36 direct + 9 namespaced branches, 49 plans merged as `171`-`208`, clones archived | okurz    | 2026-11-25 |
| Plans resolve through `git plans-dir` (primary checkout's `tasks/`), and a `post-checkout` hook links `tasks` into new worktrees (`worktree.symlink`, `worktree.setup`); the divergent `oqa-154-cleanup/tasks` copy is deleted | okurz    | 2026-11-25 |
| All duplicate plan prefixes renumbered (`209`-`218`), heading numbers normalized to the file prefix, broken references repaired | okurz    | 2026-11-25 |
| The 28 `okurz/*` upstreams that the consolidation set on pre-existing branches are unset again; branches created from clone refs keep theirs | okurz    | 2026-11-25 |
| Git operations inside `tasks/` are approved (no credentials or new internals found; the repo is public), the plan import is committed, and the push needs a separate approval | okurz    | 2026-11-25 |
| Cosmetic leftovers fixed: the 7 unresolved plan references reduced to 2 cross-repo ones, which stay | okurz    | 2026-11-25 |
| Archive carries a `DELETE-AFTER-2026-12-20.md` reminder; stale `/tmp` worktree registrations removed, worktrees without `node_modules` left alone | okurz    | 2026-11-25 |

---

## Gates

| Commit             | Scope                                                                      | Verification Command                                                                                                                                                                                                                                                                                                |
| :----------------- | :------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Commit 1 (moved)   | `git-worktree-audit` in `okurz/scripts` (`~/bin`)                          | `cd ~/bin && make test checkstyle`                                                                                                                                                                                                                                                                                 |
| Commit 2 (dropped) | `docs/Contributing.md` worktree workflow section                           | n/a, branch and commit removed 2026-11-25; patch kept in `local/155-consolidate-worktree-workflow.patch`                                                                                                                                                                                                           |
| Task 3 (no commit) | Adoption of clone refs (no bundle; filesystem backup)                     | `git worktree-audit --primary ~/local/os-autoinst/openQA oqa2 oqa3` (must exit 0 with `heads_at_risk: 0` and `remote_refs_at_risk: 0`)                                                                                                                                                                            |
| Task 4 (no commit) | Stale worktree pruned + active branches recreated as worktrees             | `git -C ~/local/os-autoinst/openQA worktree list && for w in ~/local/os-autoinst/oqa-*-*/; do make -C "$w" tidy; done`                                                                                                                                                                                              |
| Task 5 (no commit) | Clones moved to archive                                                    | `git -C ~/local/os-autoinst/openQA fsck --connectivity-only && git -C ~/local/os-autoinst/openQA worktree list && ls -ld ~/local/os-autoinst/archive/oqa*-20261120 && du -sh ~/local/os-autoinst/archive` |
| Task 6 (no commit) | Local plan documents updated                                               | `grep -rn 'oqa[2-5]' ~/local/os-autoinst/openQA/tasks/ \| grep -v '/155_'` (only checkout references rewritten; branch names such as `feature/032_oqa5_…` stay) |
| Task 7 (no commit) | Every clone head is a local branch with the clone tip                      | `for N in oqa2 oqa3 oqa4; do for b in $(git -C ~/local/os-autoinst/$N for-each-ref --format='%(refname:short)' refs/heads); do t=$(git -C ~/local/os-autoinst/$N rev-parse refs/heads/$b); p=$(git -C ~/local/os-autoinst/openQA rev-parse --verify --quiet refs/heads/clones/$N/$b \|\| git -C ~/local/os-autoinst/openQA rev-parse --verify --quiet refs/heads/$b) \|\| { echo "MISSING $N $b"; continue; }; [ "$p" = "$t" ] \|\| echo "DIFFERS $N $b"; done; done` (no output = pass) |
| Task 8 (no commit) | Clone plan files merged into `tasks/`                                      | `git -C ~/local/os-autoinst/openQA/tasks status --short` matches the pre-copy baseline plus the copied paths and `md5sum` of those paths matches the recorded source checksums |

---

## Session starter

```markdown
Continue with execution plan `tasks/155_oqa1_consolidate_worktree_workflow.md`.
Load skills: `git-workflow`, `perl-dev`, `testing`.
No branch and no worktree of its own: the former
`feature/155_…` branch and `~/local/os-autoinst/oqa-155-consolidate-worktree-workflow`
were removed on 2026-11-25 (docs patch kept in
`local/155-consolidate-worktree-workflow.patch`). Execute from
`~/local/os-autoinst/openQA` or any worktree.
The pre-deletion audit is `git worktree-audit` from `~/bin`.
All plan approvals are granted as of 2026-11-25; no permission needs re-asking,
but confirm before any move, branch creation or deletion.
State (2026-11-25): the consolidation is complete. `oqa2`-`oqa5` were adopted
into `refs/remotes/clones/*` (2013 refs), 55 clone heads became local branches,
59 plan files were merged into `tasks/`, and all four clone directories are in
`~/local/os-autoinst/archive/` (1.5G). Remaining: delete the archive not before
2026-12-20 with explicit confirmation.
Plans now resolve through `git plans-dir` in `okurz/scripts`, and the primary
checkout's `post-checkout` hook links `tasks` into every worktree
(`git config --get-all worktree.symlink`), so no manual symlink is needed.
The ruled-out variant — teaching only prompts to target the primary's `tasks/` —
is documented as insufficient: a worktree path stays git-ignored and a stray
write diverges invisibly.
Open housekeeping (done 2026-11-25): every duplicate plan prefix was resolved —
`001`→`209`, `032`→`210`, `040`→`211`, `047`→`212`, `063`→`213`, `089`→`214`,
`092`→`215`, `139`→`216`, `140`→`217`, `141`→`218`, keeping the prefix on the
file that a local branch encodes and otherwise on the older file; 23 heading
numbers were normalized to their file prefix and one reference broken by an
earlier prefix-level rewrite was corrected (`189_…_test.md` → `188_…`). The 28
branches whose `okurz/*` upstream the consolidation set without being asked had
that upstream removed again; the 8 branches created from clone refs keep theirs.
The plan surface is committed (owner-approved git actions in `tasks/`), the archive carries `DELETE-AFTER-2026-12-20.md` with the exact
verification commands, and the three stale `/tmp/opencode/*` worktree
registrations were removed (their branches and objects are untouched).
Never delete a clone directory; never push.
```
