# Implementation Plan - Fix Markdown Event List in User's Guide

This plan addresses the review comment from perlpunk regarding the formatting of the events list in the openQA User's Guide.

## Context

Review Comment URL: https://github.com/os-autoinst/openQA/pull/7751#discussion_r3804769814

Reviewer comment:

> This doesn't look nice and also didn't before this PR. Everything is on one line, hard to read.
> I assume this accidentally broke in 278e742ded86d0cf7c9714e83cdc29194e28737d

Commit `278e742ded86d0cf7c9714e83cdc29194e28737d` folded the list of openQA events (1-6) into a single line:

```markdown
1.  `openqa.job.create` when a job is created 2. `openqa.job.delete` when a job is deleted 3. `openqa.job.cancel` when a job is cancelled 4. `openqa.job.restart` when a job is restarted or duplicated 5. `openqa.job.update_result` when a job result is updated 6. `openqa.job.done` when a job finishes Job event bodies include the job settings (e.g. `BUILD`, `TEST`, `ARCH`,
```

## Solution

Restore the proper list formatting so that each event is on its own line and separated correctly. This matches how comment events (1-3) are formatted further down the page.

We will format it like this:

```markdown
Here are the events triggered and published by openQA:

1.  `openqa.job.create` when a job is created

2.  `openqa.job.delete` when a job is deleted

3.  `openqa.job.cancel` when a job is cancelled

4.  `openqa.job.restart` when a job is restarted or duplicated

5.  `openqa.job.update_result` when a job result is updated

6.  `openqa.job.done` when a job finishes

Job event bodies include the job settings (e.g. `BUILD`, `TEST`, `ARCH`,
`MACHINE`, `FLAVOR`, asset fields like `ISO` or `HDD_1`) plus `id`, `group_id`,
and `remaining` (number of pending jobs for the same build). Finished jobs
additionally include `result`, `reason`, `newbuild`, `failedmodules`, `bugref`,
and `bugurl` (only present when a bug reference exists).
```

## Verification Plan

1. Format the file using Prettier: `npm run fix`.
2. Check formatting using Prettier: `npm run lint`.
3. Check overall styling: `make test-checkstyle`.
