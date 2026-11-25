# 190 — Feature the openQA ecosystem in the documentation

## Problem

openQA has a rich ecosystem (related tools, public instances, blogs, videos,
podcasts, community channels), but it is scattered and hard to discover:

- The ecosystem list (blogs, videos, podcasts, project-management wikis,
  twitter/reddit) lives **only** in `gh-pages:documentation.html` (the open.qa
  Jekyll site) as a flat `<ul>`. It is not in the primary markdown docs.
- The primary docs (`docs/*.md`, master) → single HTML at
  https://openqa.qa/docs via `tools/generate-docs` (pandoc + perl
  `process-docs` for `include::`). They have **no** ecosystem/related-apps
  section at all.
- The public-instance list lives in the team wiki
  (progress.opensuse.org `Tools#Our-common-userbase`). The wiki is the only
  place, it is not a good entry point for newcomers, and it is a Redmine wiki
  (external, not in git) so it cannot be reviewed via PR.
- The "add your link" contributing hook exists in `documentation.html` prose
  but is not wired to a PR-friendly, structured source.

Net effect: users get a thin ecosystem page on open.qa; contributors have no
single, structured, PR-able home for the ecosystem.

## Goal

Make the docs the **single source of truth** for the ecosystem, good for users
(discovery) and for contributors (a structured, PR-able list with an explicit
"add yours" hook). Invert the current split: the docs become the authoritative
public-instance list, and the wiki list is removed and replaced with a link to
the docs. Reduce duplication between the doc surfaces.

## Proposal

### 1. New `docs/Ecosystem.md` (master) — single source of truth

Add a new top-level doc, included in `docs/index.md` (after `Contributing.md`),
so it appears in the single-page HTML at openqa.qa/docs and in the TOC.
Structure:

```
<a id="ecosystem"></a>
# Ecosystem

## Introduction            — what the ecosystem is: the tool + surrounding
                            projects, instances, community
## Related applications    — grouped, each with a one-line purpose + repo link
   - Core: openQA (web/worker), os-autoinst (backend/daemon)
   - Client & CLI: openqa-cli, openqa-clone-job, openqa-clone-cgit,
     openqa-scheduler, openqaworker-device, needle tooling, osd-deploy
   - Test libraries / distributions: os-autoinst-distri-opensuse (+ per-distri
     repos), the base test API
   - Integrations: REST/GraphQL API, InfluxDB metrics, CI hooks (the
     comment-trigger workflow in WritingTests)
## Public instances       — AUTHORITATIVE list of official + community
   instances (openqa.opensuse.org, openqa.suse.de, …), each with a short
   scope note. Seed it by capturing the full list from the wiki
   `Tools#Our-common-userbase` (read in a browser — Redmine blocks bots),
   then this file becomes the canonical home.
## Learning resources     — blogs, videos, podcasts, talks (the current
     gh-pages list, migrated here)
## Community & contributing — channels, monthly call, and an explicit
   "Add your instance / tool / blog / video via a PR to this file" hook
```

Keep it a structured list (headings + bullets), not a flat `<ul>`, so it
renders in the TOC and is easy to extend.

### 2. Rework `gh-pages:documentation.html` — link, don't duplicate

Replace the inline "Blogs and external resources" `<ul>` with a short blurb +
a single link to the ecosystem section in the docs
(`https://openqa.qa/docs#ecosystem`). Keep the "consider adding a link" hook,
pointing at the PR flow on the docs file. This removes the duplicated list and
makes open.qa a thin pointer to the canonical docs.

### 3. Cross-links from existing docs (so anchors stay referenced)

- `GettingStarted.md` intro: add a sentence + link to
  `Ecosystem.md#ecosystem` ("For the surrounding tools, instances, and
  community see the Ecosystem guide").
- `Contributing.md` "Getting involved": link to the ecosystem community
  section.
- `index.md`: add `include::Ecosystem.md[]`.

This satisfies `tools/check-markdown.py`: the new `<a id="ecosystem"></a>`
anchor is referenced from `GettingStarted.md`/`Contributing.md`.

### 4. Remove the wiki instance list — link to open.qa/docs

The wiki (`Tools#Our-common-userbase`) is a Redmine wiki, **not in git**, so
this is a coordination step with the wiki maintainer, not a git commit:

- Capture the full instance list from the wiki into `docs/Ecosystem.md`
  (section 1) first, so nothing is lost.
- Then edit the wiki page: delete the instance list and replace it with a
  one-line pointer to `https://open.qa/docs#ecosystem` (the canonical home).
- Confirm the docs section is merged and live before removing the wiki list,
  to avoid a gap where neither source lists the instances.

## Test / verification adaptations

- `make test-markdown` (runs `tools/check-markdown.py`): the new
  `ecosystem` anchor must be referenced — covered by the GettingStarted
  cross-link. Run it; it must pass.
- `make tidy` and `make test-checkstyle` must pass (markdown style).
- `make generate-docs` then `serve-docs`: confirm `Ecosystem.md` renders in
  the single-page HTML and appears in the TOC with a `#ecosystem` anchor.
- No unit/integration test changes (docs-only). If a docs build test exists,
  extend it to assert the ecosystem section is present.

## Atomic commits

1. `feat(docs): add Ecosystem guide` — new `docs/Ecosystem.md` (incl. the
   authoritative public-instance list captured from the wiki) + `index.md`
   include + GettingStarted/Contributing cross-links.
2. `refactor(gh-pages): link documentation page to ecosystem guide` —
   rework `documentation.html` to drop the duplicated list (separate commit on
   the `gh-pages` branch).
3. **External (not git):** after 1 is merged and live, ask the wiki maintainer
   to delete the instance list in `Tools#Our-common-userbase` and add a link
   to `https://open.qa/docs#ecosystem`.

## Open decisions

- **Instance list**: docs is now authoritative and mirrors the full wiki list
  (decision made). The wiki keeps only a pointer.
- **Placement in index.md**: after `Contributing.md` (community-adjacent).
- **gh-pages**: keep Jekyll, only thin the ecosystem block — do not migrate
  the whole site to markdown in this task.
