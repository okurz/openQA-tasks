# 207 — MCP write roles, tool allowlist and rate limits

Follow-up to `tasks/206_mcp_read_write_mode.md`. 127 ships the core: config
enum, role→scope plumbing, in-process API calls, read-tool gaps, operator-tier
write tools, confirmation for destructive calls. This document covers what is
configurable, the admin-tier tools, and abuse limits.

## Config

```ini
[global]
mcp_write_roles = operator      # user | operator | admin
mcp_write_tools = openqa_trigger_job openqa_restart_job openqa_duplicate_job openqa_cancel_job openqa_set_job_priority openqa_post_comment openqa_schedule_iso
mcp_write_limit = 20            # write calls per user per hour, 0 = unlimited
mcp_trigger_job_limit = 5       # openqa_trigger_job calls per user per hour
```

### `mcp_write_roles`

Minimum openQA role required for write tools. Maps onto the scopes introduced
in 127:

| value | scopes granted |
| --- | --- |
| `user` | `mcp:write` for any authenticated user |
| `operator` | `mcp:write` for operators (127 default) |
| `admin` | `mcp:write` + `mcp:admin` for admins only |

Validation: die at startup on an unknown value. `admin` is the conservative
default for admin-tier tools; `user` is an explicit opt-in for instances where
commenting/triggering by non-operators is acceptable.

### `mcp_write_tools`

Allowlist of write tool names. Tools not listed are **not registered**, so they
never appear in `tools/list` and cannot be called. Default is the operator tier
from 127. Admin-tier tools are opt-in per instance.

Implementation: the plugin registers write tools in a table
`%WRITE_TOOLS` (name → endpoint, schema, annotations, required role).
Registration loop:

```perl
my %allowed = map { $_ => 1 } split ' ', ($config->{write_tools} // '');
for my $name (sort keys %WRITE_TOOLS) {
    my $def = $WRITE_TOOLS{$name};
    next unless $allowed{$name};
    next if $def->{role} eq 'admin' && $config->{write_roles} ne 'admin';
    $mcp->tool(name => $name, scopes => [$def->{scope}], %$def);
}
```

Keeping the allowlist at registration time (not call time) means the LLM never
sees a tool it cannot use, which avoids failed calls and token waste.

### Admin-tier tools (opt-in)

| Tool | Endpoint reused | Role | Notes |
| --- | --- | --- | --- |
| `openqa_create_job_template` | `POST /api/v1/job_templates` | admin | |
| `openqa_update_job_templates_scheduling` | `POST /api/v1/job_templates_scheduling/<id>` | admin | YAML/JSON scheduling blob, the `openqa-cli api` workflow |
| `openqa_create_job_group` / `openqa_update_job_group` | `POST`/`PUT /api/v1/job_groups` | admin | |
| `openqa_create_product` / `openqa_update_product` | `table#create`/`update` (`Products`) | admin | |
| `openqa_create_machine` / `openqa_update_machine` | `table#create`/`update` (`Machines`) | admin | |
| `openqa_create_test_suite` / `openqa_update_test_suite` | `table#create`/`update` (`TestSuites`) | admin | |
| `openqa_delete_asset` | `DELETE /api/v1/assets/<id>` | admin | `destructiveHint => 1`, confirmation required |
| `openqa_delete_needle` | `DELETE /admin/needles/delete` | admin | `destructiveHint => 1`, confirmation required |
| `openqa_kill_worker` | `DELETE /api/v1/workers/<id>` | operator | `destructiveHint => 1`, confirmation required |

Excluded on purpose: `DELETE /api/v1/user/<id>`, `DELETE /api/v1/users/me`,
`DELETE /api/v1/jobs/<id>` (deleting a job record is not a supported
operation), `POST /api/v1/users/me/api_keys`.

## Rate limiting

`mcp_write_limit` caps write calls per user per hour; `mcp_trigger_job_limit`
caps the resource-consuming tool specifically. Options:

1. **Count audit events** (`AuditEvents` with the `mcp` marker in
   `event_data`, `user_id`, `created` in the last hour). No schema change,
   reuses the 127 marker. Requires `audit_enabled = 1`; if auditing is off,
   rate limiting cannot work — log a warning and refuse `read-write`.
   Cost: a JSON-text scan per call; index `audit_events (user_id, created)`
   and filter by event type, not by the JSON payload.
2. **Dedicated table** `mcp_calls (user_id, tool, created)` with a `dbicdh`
   migration (next `_source/deploy` version after 99). Works with auditing
   disabled, supports per-tool limits, cheap count query, easy to prune with a
   gru job. Cost: schema change plus a write per call.
3. In-memory per-worker counter (`Mojo::Cache`): not shared across hypnotoad
   workers, so limits are effectively multiplied by the worker count. Reject.

Recommendation: option 2, with the audit marker kept for the UI. Enforce in the
tool wrapper before dispatch:

```perl
sub _check_limit ($c, $user, $tool, $config) {
    my $limit = $tool eq 'openqa_trigger_job' ? $config->{trigger_job_limit} : $config->{write_limit};
    return 1 unless $limit;
    return $c->schema->resultset('McpCalls')->search(
        {user_id => $user->id, tool => $tool, created => {'>=', now - ONE_HOUR}})->count < $limit;
}
```

When the limit is hit, return a tool error (`isError`) naming the limit and the
window, so the LLM can back off rather than retry.

## Tests

- `t/api/18-mcp_write.t` (from 127) extended:
  - `mcp_write_roles = admin`: operator loses write tools in `tools/list`
  - `mcp_write_roles = user`: non-operator gains `openqa_post_comment`
  - `mcp_write_tools` allowlist: unlisted tool absent from `tools/list` and
    404 on call
  - admin-tier tools: job template create, product create, asset delete with
    confirmation
  - rate limit: N calls succeed, N+1 fails with the limit message; per-tool
    trigger limit
  - `mcp_write_limit` with `audit_enabled = 0` (option 2: works; option 1:
    refuses `read-write`)
- `t/ui/05-auth_mcp.t`: MCP help page lists enabled tools per mode.
- `COVERAGE=1 make test-unit-and-integration TESTS=t/api/18-mcp_write.t`,
  `make check-line-coverage`, `make tidy`, `make test-checkstyle`,
  `make test-gitlint`.

## Atomic commits

1. `feat(mcp): add admin-tier write tools`
2. `feat(config): add mcp_write_roles and mcp_write_tools`
3. `feat(db): track MCP write calls for rate limiting`
4. `feat(mcp): enforce per-user write rate limits`
5. `feat(ui): list enabled MCP tools on the MCP help page`
6. `docs(mcp): document write roles, tool allowlist and rate limits`

## Open questions

- Per-tool limits for every write tool, or just the global limit plus
  `openqa_trigger_job`? Starting with two knobs keeps the config small.
- Should the rate-limit window be a rolling hour (count query) or a fixed
  window (counter row)? Rolling hour is simpler and needs no reset job.
- Pruning `mcp_calls`: gru job reusing the existing `OpenQA::JobLimitation` /
  `minion_task_triggers` mechanism, or a `dbicdh`-style cleanup in the
  existing `OpenQA::Schema::Result::Jobs::set_done` family?
- Is `openqa_delete_asset` worth exposing at all, given the confirmation flow
  and the fact that asset deletion is usually automated by gru jobs?
