# 181 Opt-in restart confirmation threshold

Theme: `174_job_impact_theme_overview.md`. Depends on: 129.

## Goal

Let admins add friction for expensive or repeated **manual** restarts, without
blocking them. This is disabled by default (decision: opt-in).

## Commit 1: feat(config): add restart confirmation thresholds

- `[job_impact]` gets three new keys:
  - `confirm_restart_above_cost` (empty = off), in the configured currency.
  - `confirm_restart_above_carbon_g` (empty = off).
  - `confirm_restart_after_manual_restarts` (empty = off): the number of
    previous `restart_origin = user` ancestors, from task 126.
- Validate them in `read_config` (numbers >= 0).
- Tests: `t/config.t`.

## Commit 2: feat: flag restarts that need confirmation

- `restart_estimate` (task 129) adds `confirmation => {required => bool,
reasons => [...]}`, based on the thresholds.
- Server-side enforcement is deliberately **not** done:
  - API, CLI and automation must stay unaffected.
  - The UI dialog is a nudge, not an access control.
  - Document this in `docs/JobImpact.md`.
- Tests: `t/job_impact_restart.t`, data-driven: each threshold alone, the
  thresholds combined, and all disabled.

## Commit 3: feat(webui): show confirmation dialog above threshold

- `assets/javascripts/job_impact.js`: before `restartJob()` sends its POST, if
  `confirmation.required`, show a Bootstrap modal (not `window.confirm`)
  containing:
  - the estimate and the reasons, e.g. "already restarted manually 2 times";
  - a link to the Investigation tab;
  - an optional comment field. When filled, the comment is posted with the
    existing restart-with-comment mechanism.
  - Buttons "Restart anyway" and "Cancel".
- The overview bulk restart uses the same modal with the summed estimate.
- Tests: in `t/ui/18-tests-details.t` and `t/ui/10-tests_overview.t`:
  - with a threshold configured, the modal appears; "Cancel" creates no clone;
    "Restart anyway" creates the clone;
  - without a threshold there is no modal (default behavior unchanged).

## Acceptance

- Default installs show no dialog.
- With thresholds configured, the dialog appears only for manual UI restarts
  that exceed a threshold.

## Status

Implemented on branch `feature/130_restart_confirmation_threshold`:

- Commit: `82cf3a306 feat: add opt-in restart confirmation threshold`

Verification:

- `make tidy` and `make test-checkstyle` passed cleanly.
- `make test-gitlint` passed across all commits.
- Full statement coverage verified on all modified lines.
