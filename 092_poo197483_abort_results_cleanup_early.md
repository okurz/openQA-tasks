# Execution Plan: Fair JobGroup Handling for Disk Cleanup Early Aborts

## Context & Motivation
Following the implementation of early aborts during disk space cleanup (to prevent load surges via `#197483`), a fairness issue was identified during code review: iterating over `JobGroups` in default database order (`id ASC`) systematically penalizes the oldest groups (they are always cleaned up first) and spares newer groups when early aborts trigger.

We considered four alternatives to the initially suggested random `shuffle()` (which obscures observability):
- **Option A:** Sort by `COUNT(jobs.id) DESC` (Largest volume first)
- **Option B:** Sort by `MIN(jobs.id) ASC` (Oldest data first)
- **Option C:** Stateful Round-Robin tracking
- **Option D:** Global Age-Based Cleanup (Architectural overhaul)

Benchmarks on the live production database (processing ~4.3M rows) proved that DBIx::Class aggregation queries (Options A/B) add a negligible ~2.5 second overhead to a daily Minion job that otherwise takes hours.

### Why reject Option B (`MIN(jobs.id) ASC`)?
Sorting by the lowest absolute job ID permanently penalizes JobGroups configured with intentionally long retention periods (e.g., LTS releases). They will always possess the lowest `jobs.id` and will be repeatedly targeted for cleanup first, while fast-moving groups (e.g., Factory) with newly expired jobs might be skipped if the loop aborts early. This violates the semantics of retention policies.

## Implementation Plan

We will proceed with a phased approach:

### Phase 1: Implement Option A (`COUNT(jobs.id) DESC`) - Immediate Fix
**Goal:** Break the static insertion-order bias immediately using a stateless, logical heuristic: clean the heaviest users first. Groups generating the most jobs are statistically the most likely to be consuming disk space.

**Task 1.1: Modify JobGroup Iteration Query**
- **File:** `lib/OpenQA/Task/Job/Limit.pm`
- **Action:** Update the `$schema->resultset('JobGroups')` query used for the cleanup loop.
- **Details:** Add `join => 'jobs'`, `group_by => ['me.id', 'me.name']`, and `order_by => 'COUNT(jobs.id) DESC'` to the search parameters.

**Task 1.2: Verify and Commit**
- **Action:** Run `make test-unit-and-integration TESTS=t/42-df-based-cleanup.t` and `make test-checkstyle`.
- **Commit:** Create an atomic commit specifically for this sorting change to clearly separate it from the previous logging improvements.

### Phase 2: Implement Option C (Stateful Round-Robin) - Future Enhancement
**Goal:** While Option A targets the biggest consumers, it may delay cleanup for small, low-traffic groups. To guarantee perfect fairness over time, we will implement a stateful round-robin iteration.

**Task 2.1: Implement State Storage Mechanism**
- **Concept:** Create a mechanism to persist the `id` of the last processed `JobGroup` between Minion job invocations.
- **Design Choice:** Avoid altering the DB schema. Utilize a local state file, heavily inspired by the existing `asset-status.json` implementation in `lib/OpenQA/Schema/ResultSet/Assets.pm`.
- **Implementation:**
  - Define a constant path (e.g., `prjdir() . '/webui/cache/cleanup-status.json'`).
  - Create helper methods to read/write the `last_processed_job_group_id` using `Mojo::JSON::encode_json`/`decode_json` and `Feature::Compat::Try`.

**Task 2.2: Refactor Cleanup Loop Iteration**
- **File:** `lib/OpenQA/Task/Job/Limit.pm`
- **Action:**
  - Retrieve `last_processed_job_group_id` from the cache file.
  - Query all JobGroups.
  - Partition or sort the array of JobGroups so that the loop begins with the ID immediately following `last_processed_job_group_id`, wrapping around to the beginning.
  - After processing a group, update the cache file.

**Task 2.3: Verification**
- **Action:** Add specific unit tests in `t/42-df-based-cleanup.t` to verify the state file is created, updated correctly, and heavily dictates the starting point of the next cleanup run.
- **Commit:** Commit this as a separate architectural enhancement.