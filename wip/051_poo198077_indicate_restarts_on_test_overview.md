# Execution Plan for Ticket 198077: Indicate previous restarts/clones in job lists

## Overview

The goal is to show job restart/clone information directly in job lists (e.g., the `/tests/overview` page). Currently, this data is only visible inside individual job details. We will fulfill AC1 by displaying a small counter with an icon (e.g., `<i class="fa fa-undo"></i> 2`) for jobs that have been restarted.

## Tasks

### 1. Backend: Implement Bulk Ancestors Retrieval

**File:** `lib/OpenQA/Schema/ResultSet/Jobs.pm`

- Add a new method `ancestors_count_for_jobs($self, $job_ids)` that retrieves the number of ancestors for an array of job IDs using a single recursive CTE query. This prevents the N+1 query problem when loading the overview table.
- The SQL should logically mirror the existing `ancestors` method but optimized for multiple initial IDs:
  ```perl
  sub ancestors_count_for_jobs ($self, $job_ids) {
      return {} unless $job_ids && @$job_ids;
      my $dbh = $self->result_source->schema->storage->dbh;
      my $placeholders = join(',', ('?') x @$job_ids);
      my $sth = $dbh->prepare("
          with recursive orig_id as (
              select id as initial_id, id as orig_id, 0 as level from jobs where id in ($placeholders)
              union all
              select initial_id, jobs.id as orig_id, orig_id.level + 1 as level
              from jobs
              join orig_id on orig_id.orig_id = jobs.clone_id
              where orig_id.level < 100
          )
          select initial_id, max(level) - 1 as restarts from orig_id group by initial_id;
      ");
      $sth->execute(@$job_ids);
      my %result;
      while (my ($id, $level) = $sth->fetchrow_array) {
          $result{$id} = $level;
      }
      return \%result;
  }
  ```

### 2. Backend: Calculate Ancestors in Overview Data Preparation

**File:** `lib/OpenQA/WebAPI/Controller/Test.pm`

- In `_prepare_job_results`, add `my $ancestors_by_job = {};` near other batch-fetched hashes.
- Inside the `unless ($only_aggregated)` block, fetch the batch ancestor mapping:
  `$ancestors_by_job = $schema->resultset('Jobs')->ancestors_count_for_jobs([map { $_->id } @jobs]);`
- Update the `$job->overview_result(...)` method call to pass the fetched ancestor count as a new parameter: `$ancestors_by_job->{$id} || 0`.

### 3. Backend: Append Restart Count to Job Result Data

**File:** `lib/OpenQA/Schema/Result/Jobs.pm`

- Update the signatures of `overview_result` and `_overview_result_done` to accept a new `$ancestors_count` parameter.
- Inside `_overview_result_done`, add `restarts => $ancestors_count` to the returned hash.
- In `overview_result`, pass `$ancestors_count` to `_overview_result_done` and ensure it's also added to the returned `$result` hash map when returning intermediate (non-DONE) states.

### 4. Frontend: Display Restart Counter in the Job List

**File:** `templates/webapi/test/tr_job_result.html.ep`

- Utilize the `restarts` value from the provided `$res` structure to render an indicator.
- Add an HTML block near the other job result details that renders a `fa-undo` icon and the restart number if `restarts > 0`:
  ```html
  % if ($res->{restarts}) {
  <span class="restarts" title="Restarted <%= $res->{restarts} %> time<%= $res->{restarts} != 1 ? 's' : '' %>">
    <i class="fa fa-undo"></i> <%= $res->{restarts} %>
  </span>
  % }
  ```
- Ensure this span aligns nicely with other inline elements like dependencies and failed modules.

### 5. Verification & Testing

- Create or adapt tests inside `t/10-tests_overview.t` or UI tests (e.g. `t/ui/10-tests_overview.t`) to ensure the restart counter correctly appears for cloned jobs.
- Validate that `make tidy` and `make test-checkstyle` execute without failure prior to committing.
- Ensure the changes cause no regressions in existing dashboard or overview page behavior.
