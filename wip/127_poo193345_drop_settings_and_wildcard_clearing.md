# 127*poo193345: Remove groups of settings via `_DROP_SETTINGS` and `+VAR*\*=`

Follow-up of https://progress.opensuse.org/issues/193345.

## Problem

Clearing posted assets currently requires one `+VAR=` per setting, e.g.
`+ISO= +ASSET_1= +ASSET_2= +ASSET_256= +ASSET_LIBVIRT= +ASSET_VIRTUALBOX=`.
This is verbose and breaks silently when the trigger adds a new `ASSET_*`.
Also cleared settings remain on the job as empty strings.

## Design

Both variants are applied in `finalize_job_settings`
(`lib/OpenQA/JobSettings.pm:34-43`) after `handle_plus_in_settings` and before
`expand_placeholders`, so they cover isos post
(`ScheduledProducts.pm:621`, `:820`) and `POST /api/v1/jobs`
(`API/V1/Job.pm:1037`). Matching keys are _deleted_, not set to empty.

1. Commit A: `_DROP_SETTINGS`: comma-separated list of setting names, each
   may contain `*` as wildcard (glob, anchored), e.g.
   `_DROP_SETTINGS=ISO,ASSET_*`. Applied last, so it beats every source
   including POST parameters. `_DROP_SETTINGS` itself is kept on the job for
   traceability and is never matched by its own patterns. Regular
   precedence decides which `_DROP_SETTINGS` value applies; document using
   `+_DROP_SETTINGS` when combining with posted values.
2. Commit B: wildcard clearing `+ASSET_*=`: a `+` key containing `*` deletes
   all matching keys. Only allowed with an empty value (clearing), a
   non-empty value is rejected with an error to avoid ambiguous semantics.
   Implemented via the same matching helper as commit A.
   - Allow `*` in setting keys: `public/schema/JobTemplates-01.yaml:54`,
     `public/schema/JobScenarios-01.yaml:43`, and check key validation for
     test suite/machine/product settings in the web UI/API
     (`lib/OpenQA/WebAPI/Controller/API/V1/Table.pm`).

## Docs

- [ ] `docs/UsersGuide.md:283-305` (precedence / `+`): document both.
- [ ] `docs/UsersGuide.md:1513-1560` (assets): recommend `_DROP_SETTINGS` for
      jobs that do not use posted assets.

## Tests

- [ ] `t/40-job_settings.t` (next to `handle_plus_in_settings`, `:118`),
      data-driven: plain names, globs, no match, `_DROP_SETTINGS` not
      self-deleting, interaction with `+VAR`, placeholders referencing a dropped
      setting stay unexpanded, `+ASSET_*=foo` yields an error.
- [ ] `t/api/02-iso.t`: isos post with test suite `_DROP_SETTINGS=ISO,ASSET_*`
      and with `+ASSET_*=` → jobs have no such settings and no `jobs_assets`
      rows for them.
- [ ] Job template YAML test accepting a `+ASSET_*` key
      (`t/api/08-jobtemplates.t`) and the test suite table API.
- [ ] Full statement coverage via `COVERAGE=1` + `make check-line-coverage`.

## Commits

- `feat(settings): Add _DROP_SETTINGS to remove settings from jobs`
- `feat(settings): Support wildcards in +VAR settings for clearing`
