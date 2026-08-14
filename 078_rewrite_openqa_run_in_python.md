# Task 078: Rewrite openqa-run in Python

## Goal
Rewrite the `tools/openqa-run` bash script in Python using the `typer` library and address reviewer feedback from PR #5796.

## Reviewer Feedback to Address
1. **User Account**: Remove `sudo -u geekotest`. Run as the current user.
2. **Base Directory**: 
   - Clarify `OPENQA_BASEDIR` usage.
   - Consider the risk of cluttering `t/data`.
3. **Usability**:
   - Ensure help is clear.
   - Address the "not in PATH" concern by being explicit about what is called.

## Implementation Plan
1. Create `tools/openqa-run` as a Python script using `typer`.
2. Implement the following features:
   - `--basedir` option (defaulting to `t/data` if not set in environment).
   - Positional arguments for the command to run.
   - Set environment variables and execute the command.
3. Update `docs/Contributing.md` (or `.asciidoc` if it's still that) to reflect the changes and clarify `OPENQA_BASEDIR`.

## Verification
1. Run `tools/openqa-run --help`.
2. Run a simple command like `tools/openqa-run env` and verify `OPENQA_BASEDIR` is set.
3. Run `make tidy` and `make test-checkstyle`.
