# 158 gh-pages: Link the Ecosystem guide instead of duplicating it

Context: `dffee40` ("feat(docs): add Ecosystem guide", master, 2026-10-15)
added `docs/Ecosystem.md` as the single, PR-able source for related projects,
public instances, learning resources and community. The `gh-pages` branch still
hand-maintains substantially the same lists in `documentation.html`, so open.qa
and `docs/Ecosystem.md` drift apart (already visible: X/Twitter, Codethink,
Reddit and progress.opensuse.org entries differ).

The generated documentation on gh-pages (`docs/index.html`, `docs/current.pdf`)
already contains the guide because the docs bot copies master `docs/` there. The
anchor `<a id="ecosystem"></a>` / `<h1 id="ecosystem">` is present, so
`/docs/#ecosystem` is a valid target.

Branch: `feature/158_oqa1_gh_pages_ecosystem_dedup` (based on
`origin/gh-pages`, worktree `~/local/os-autoinst/oqa-158-gh-pages-ecosystem`).
Target: PR to `os-autoinst/openQA:gh-pages` from `okurz` fork.

## Goal

- Remove the duplicated "Videos" and "Blogs and external resources" sections
  from `documentation.html` on gh-pages.
- Replace them with one short pointer to the Ecosystem guide in the generated
  docs and PDF, including the existing "add yours via PR" hook.
- Leave `index.html`, `downloads.html`, `contact.html`, layouts, styles and
  generated `docs/` untouched.
- No change to `master` in this branch.

## Decisions (pending confirmation)

| Decision                                                                   | Approver             | Date |
| -------------------------------------------------------------------------- | -------------------- | ---- |
| Remove both duplicated sections in one commit                              | pending confirmation | -    |
| Keep `contact.html` (chat channels are not in the Ecosystem guide)         | pending confirmation | -    |
| Accept dropping the few gh-pages-only links (see Risks)                    | pending confirmation | -    |
| Migrate those unique links to `docs/Ecosystem.md` via a separate master PR | pending confirmation | -    |
| Push to `okurz` and open the PR only after this plan is approved           | pending confirmation | -    |

## Task 1 (Commit 1): Replace duplicated sections with a pointer

File: `documentation.html` in the worktree.

Delete lines 63-95 today: the whole second `<div class="row">` containing
`<h2>Videos</h2>` and `<h2>Blogs and external resources</h2>`. Replace with:

```html
<div class="row">
  <div class="col-md-12">
    <h2>Videos, blogs and external resources</h2>
    <p>
      Videos, blogs, podcasts, public instances and community channels are collected in the
      <a href="{{ site.baseurl }}/docs/#ecosystem">Ecosystem guide</a>. It is part of the generated documentation (also
      available as <a href="{{ site.baseurl }}/docs/current.pdf">PDF</a>) and can be extended with a pull request to
      <a href="https://github.com/os-autoinst/openQA/blob/master/docs/Ecosystem.md">docs/Ecosystem.md</a>.
    </p>
  </div>
</div>
```

Use `{{ site.baseurl }}` like the existing `/docs/` links; `site.baseurl` is
empty on open.qa, so the link resolves against the `CNAME` root.

Commit message:

```
docs(gh-pages): Link Ecosystem guide instead of duplicating it

The guide in docs/Ecosystem.md is the single source for related
projects, instances, learning resources and community. open.qa still
maintains the same lists by hand, so the two copies drift. Replace the
duplicated sections with a link to the generated guide.
```

`tasks/` is excluded via `.git/info/exclude`; only `documentation.html` is
staged.

## Task 2 (deferred, separate master PR): Preserve unique links

Only if approved. Move entries that currently exist only on gh-pages into
`docs/Ecosystem.md` on a `master`-based branch:

- `https://www.codethink.co.uk/articles/2023/testing-in-a-box-blog/` (the
  guide links the same talk on YouTube, not this article).
- `https://progress.opensuse.org/projects/openqav3/wiki` is already covered by
  the project page link; `https://progress.opensuse.org/projects/qa/wiki` is
  SUSE QE generic, not openQA-specific, so it may stay dropped.
- Re-check the remaining differences before submitting; the guide is the
  target, not a copy of the current gh-pages list.

## Gates

Run in `~/local/os-autoinst/oqa-158-gh-pages-ecosystem` before committing:

```
git diff --check
xmllint --html --noout documentation.html      # must print nothing
grep -nE 'Videos|Blogs and external resources' documentation.html  # no hits
grep -n 'docs/#ecosystem' documentation.html                       # one hit
git show origin/gh-pages:docs/index.html | grep -c 'id="ecosystem"'  # >= 1
```

Notes:

- There is no test suite on gh-pages (no `Makefile`, no `t/`); the lint/HTML
  checks above are the equivalent gate. `xmllint` currently emits
  `Unexpected end tag : p` for the old section, so a clean run also proves the
  broken `<p><ul>...</p>` nesting is gone.
- Jekyll cannot be built from this branch alone (no `Gemfile`); do not add one
  just for this change.
- A GitHub PR to `gh-pages` is not covered by the master workflows. The daily
  docs bot only touches `docs/index.html` and `docs/current.pdf`, not the
  static pages.

After commit: `git show --stat HEAD` must show only `documentation.html`.

## PR (after approval)

```
git push -u okurz feature/158_oqa1_gh_pages_ecosystem_dedup
gh pr create --repo os-autoinst/openQA --base gh-pages \
  --head okurz:feature/158_oqa1_gh_pages_ecosystem_dedup \
  --title "docs(gh-pages): Link Ecosystem guide instead of duplicating it"
```

PR body: state that the guide was added in `dffee40`, that the static page
duplicated it and had started to drift, and that the link targets
`/docs/#ecosystem` which the docs bot already publishes. Mention the optional
master follow-up for gh-pages-only links. Do not claim the implementation or a
test proves more than the gates above.

## Risks

- Base branch is not `master`; selecting the wrong PR base silently targets the
  wrong tree.
- Dropped links: openqa-bites, Liv's blog, Reddit, X, progress.openSUSE, QA
  monthly call, Linux Inlaws, Codethink and the three video searches. All have
  an equivalent in `docs/Ecosystem.md` except the Codethink 2023 blog article
  and the SUSE QE generic wiki (see Task 2).
- If the docs bot has not yet published Ecosystem on gh-pages, `#ecosystem`
  would dead-end; the gate above checks the current tip and the commit is 5
  weeks old, so this should be stable.
- gh-pages accumulates bot commits; rebase the feature branch if it conflicts
  before opening or updating the PR.

## Session starter

Exact prompt for the next session:

```
Execute tasks/158_oqa1_gh_pages_ecosystem_dedup.md (openQA repo), Task 1 only.
Load skills: git-workflow, openqa.
Work only in the existing worktree ~/local/os-autoinst/oqa-158-gh-pages-ecosystem
on branch feature/158_oqa1_gh_pages_ecosystem_dedup (base origin/gh-pages).
Do not touch master or other gh-pages files. Replace the duplicated Videos and
Blogs sections in documentation.html with the pointer from the plan, run every
Gate command, commit as specified, then make test-gitlint. Report the gate
results. Do not push or open the PR; stop and ask for approval first.
```
