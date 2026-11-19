# Plan: Revise definition of "scenario" (aka koala) in documentation

## Motivation
With the merger of qem-bot#655, jobs can now have a proper `SUBMISSION_ID` to isolate them into separate job histories, even if they share the same scenario string. The definition of a "scenario" (aka "koala") currently implies it strictly defines a single consecutive history. We need to update this definition to account for the new history isolation mechanism.

## Proposed Changes
1. **docs/GettingStarted.md**:
   - Locate the definition of **scenario** (around line 144).
   - Update the definition to clarify that while it establishes the "base identity" of a test for grouping jobs into a common history, it can be further subdivided into independent histories using isolation keys (like `SUBMISSION_ID`) to separate unrelated test campaigns (e.g. pull requests, incidents).
2. **docs/UsersGuide.md** (Review):
   - The UsersGuide already documents `SUBMISSION_ID` and history isolation properly. No structural definition rewrite is needed here, just ensuring the concept is clear if "koala" is mentioned.

## Acceptance Criteria
- Definition of `scenario` in `GettingStarted.md` correctly mentions the use of `SUBMISSION_ID` for history isolation.
- Explains how this allows jobs sharing the same scenario to still be treated separately for "Next & Previous", bug carry-over, etc.
