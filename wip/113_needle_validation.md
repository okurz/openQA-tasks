# 113 Needle filename validation on save (configurable rules)

## Problem

The openQA needle editor already suggests a correctly-formatted needle name
(via `ensure_timestamp_appended`, appending `-YYYYMMDD`), but does NOT validate
the name the user actually submits when pressing "Save". Users can override the
suggestion with an invalid name (e.g. missing/invalid timestamp suffix). The
mistake only surfaces later in the needle repository's own CI (see
`../os-autoinst-needles-tests/test.py`), producing errors like:

```
Needle 'firefox_pdf-firefox-pdf-page-20260813-sle12' has missing or invalid
timestamp suffix (valid suffixes: -YYYYMMDD or -YYYYMMDD_n with n=0…99)
```

Goal (per SUSE chat, S. Zarate / G. Wang): openQA should either block saving an
invalid needle name at save time, or otherwise handle it, so mistakes are
caught in the webUI instead of downstream CI.

## Scope decision

Implement **server-side validation on save** with a **configurable rule set**,
plus **client-side pre-check** for immediate UX feedback. The authoritative
check lives server-side; the client check only avoids a round-trip.

Configuration layering (in priority order, later overrides earlier):

1. Built-in defaults: the rule set ported from `test.py`, but **disabled by
   default** (`validation = disabled`) to avoid surprising existing
   deployments. Operators opt in per instance.
2. Per-instance config in `openqa.ini` (new `[needles]` section).
3. Per-needle-repository config: an optional `.openqa-needle-validation.yaml`
   file at the root of the `NEEDLES_DIR` git checkout, so each needle repo can
   declare its own rules (this maps the existing `test.py` rules into the repo
   itself). Only honored when the needledir resolves to a known, configured git
   path.

## Rules to support (mirroring `../os-autoinst-needles-tests/test.py`)

The reference CI enforces (from `test.py`):

- `timestamp`: name must end with a valid timestamp suffix
  `-YYYYMMDD` or `-YYYYMMDD_n` (n = 0…99), year ≥ 2013.
- `workaround_bugref`: if JSON `properties` contains `workaround`, the name
  must contain a bug reference
  (`(poo|bsc|bnc|boo|kde)#?[A-Z0-9]+` or `jsc#?[A-Z]+-[0-9]+`).
- `single_click_area`: at most one `area` with `type=click`.

Model these as a small ordered list of named rules, each toggleable and each
carrying its own error message. Start by porting the three rules above so
openQA's save-time check is a superset of the repo CI and mistakes never reach
CI.

## Design

### Config

`lib/OpenQA/Setup.pm` — add a `needles` section to the `$defaults` hash:

```perl
needles => {
    validation => 'disabled',   # 'disabled' | 'warn' | 'block'
    validation_rules => 'timestamp,workaround_bugref,single_click_area',
},
```

`etc/openqa/openqa.ini` — document a new commented `[needles]` block mirroring
the `[scm git]` doc style, including how to enable per-repo config.

### Validation module (new)

`lib/OpenQA/Needles/Validation.pm` (new module) with:

- `validate_needle_name($name, $json_hashref, \%rules)` returning a list of
  error strings (empty = valid).
- Individual rule subs (`_rule_timestamp`, `_rule_workaround_bugref`,
  `_rule_single_click_area`) keyed by name so the enabled set is data-driven
  and matches `validation_rules` config.
- A loader `load_repo_rules($needledir)` that reads an optional
  `.openqa-needle-validation.yaml` at the needledir root and merges/overrides
  the instance rules. Parse with the existing `OpenQA::YAML::load_yaml` helper
  (`lib/OpenQA/YAML.pm:43`, backed by `YAML::PP` — no new dependency). Guard
  against path traversal; only read within the resolved
  (realpath) needledir. Malformed YAML → log a warning and fall back to instance
  rules (do not crash the save).

Keep regexes identical to `test.py` to avoid behavioral drift; add a code
comment cross-referencing `os-autoinst-needles-tests/test.py` as the source of
truth for the rule semantics.

### Wiring into save path

`lib/OpenQA/WebAPI/Controller/Step.pm` `save_needle_ajax` (currently lines
401-413): after the existing `$validation->...` block and after resolving
`$needledir`/`$needlename` (lines 418-419) and decoding the submitted JSON,
call the new validator when mode is `block`:

- mode `disabled`: skip.
- mode `block`: on any errors, return a JSON validation error (reuse the
  existing `reply->validation_error` / a structured `{error => ...}` render so
  the frontend flash shows the messages) with HTTP 400; do NOT enqueue the
  `save_needle` Gru task.
- mode `warn`: enqueue the save as today but include the warnings in the JSON
  response so the frontend can surface them non-blockingly.

The JSON body needs to be decoded here to feed the workaround/click-area rules.
`json` param is already required (line 407); decode it once and reuse.

### Frontend

`assets/javascripts/needleeditor.js` `saveNeedle` (line 475): add a
client-side pre-check mirroring the timestamp rule (cheap, name-only) before
the POST for instant feedback, and render server-returned validation
errors/warnings in the existing flash area (the code already handles
`requires_overwrite`; extend the response handling for a new
`validation_errors` field). Keep the server as the source of truth.

`templates/webapi/step/edit.html.ep`: no structural change required; error
display reuses existing flash.

## Tests

- `t/` unit test for `OpenQA::Needles::Validation`: data-driven, parametrized
  table of `{name, json, rules, expected_errors}` covering:
  - valid `-YYYYMMDD` and `-YYYYMMDD_n` (n=0, n=99) names → no error.
  - invalid: no suffix, `n=100`, year < 2013, non-numeric → timestamp error.
  - workaround property with/without bugref (poo/bsc/jsc variants).
  - 0/1/2 click areas.
  - repo-config override: a fixture needledir with
    `.openqa-needle-validation.json` disabling a rule.
  - the exact failing example from the chat
    (`firefox_pdf-firefox-pdf-page-20260813-sle12`) → timestamp error, and its
    corrected form → pass.
- Controller/integration test extending the existing needle-save test
  (`t/ui/...` covering `save_needle_ajax`): with `validation=block` an invalid
  name returns 400 and does NOT write files / enqueue save; with `disabled`
  behavior is unchanged (regression guard).
- Coverage: run `COVERAGE=1 make test-unit-and-integration TESTS=...` for the
  new/edited test files, then `make check-line-coverage` for full statement
  coverage of the new module and edited lines.
- `make tidy` and `make test-checkstyle` before committing.

## Commit breakdown (atomic)

1. `feat: Add configurable needle filename validation module` — new
   `Validation.pm` + `[needles]` config defaults + ini docs + unit tests.
2. `feat: Enforce needle validation on save in the needle editor` — wire into
   `save_needle_ajax` (block/warn modes) + controller/integration test.
3. `feat: Add client-side needle name pre-check in the editor` — `neededitor.js`
   changes + surface server validation messages.

(If maintainers prefer, 2 and 3 can be squashed; keep 1 separate.)

## Open questions (confirm with maintainers before implementing)

1. Default mode: ship `disabled` (opt-in, safest for existing instances) vs.
   `block` (matches the chat's "should be blocked"). Recommend `disabled`
   default + document enabling `block`, letting o3.<internal>/OSD opt in.
2. Per-repo config format & filename: JSON (`.openqa-needle-validation.json`)
   vs. reuse ini. JSON is simplest to parse and matches needle files.
3. Should openQA's rule set be the single source of truth and the needle-repo
   CI (`test.py`) then just call openQA's validator, to avoid two copies of the
   regexes? Longer-term dedup opportunity; out of scope for the first PR but
   worth noting.

## Key references

- CI rules source of truth: `../os-autoinst-needles-tests/test.py:43-55`.
- Save route: `lib/OpenQA/WebAPI.pm:200`.
- Save controller + current validation: `lib/OpenQA/WebAPI/Controller/Step.pm:401-413`.
- Disk write + git commit: `lib/OpenQA/Task/Needle/Save.pm:52-168`.
- Timestamp helper: `lib/OpenQA/Utils.pm:280` (`ensure_timestamp_appended`).
- needledir/NEEDLES_DIR + git auto-clone: `lib/OpenQA/Utils.pm:277,588-597`.
- Config defaults: `lib/OpenQA/Setup.pm:165` (`[scm git]` block as pattern).
- ini docs pattern: `etc/openqa/openqa.ini:152-181`.
- Frontend save: `assets/javascripts/needleeditor.js:475,644`.
