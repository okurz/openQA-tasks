# 206 — MCP read+write mode (core)

Scope: config gate, role-based scopes, in-process API calls, read-tool gaps,
operator-tier write tools, confirmation for destructive calls, docs/UI/tests.
Configurable role gating, tool allowlist, rate limiting and admin-tier write
tools are in `tasks/207_mcp_write_roles_tools_and_limits.md`.

## Current state

- `lib/OpenQA/WebAPI/Plugin/MCP.pm` registers 3 tools (`openqa_get_info`,
  `openqa_get_job_info`, `openqa_get_log_file`), all annotated
  `readOnlyHint => 1`. Route: `under('/')->to('Auth#auth')` then
  `any('/mcp' => $mcp->to_action)`.
- `to_action` is called without options, so the transport's `auth` hook is
  unset. `MCP::Server::Transport::HTTP` therefore never populates
  `$c->stash('mcp.auth')`, and `MCP::Server::Context::has_scope` is inert: the
  library's per-primitive `scopes` mechanism is currently unused.
- `lib/OpenQA/Setup.pm:538` loads the plugin only for `mcp_enabled eq
  'read-only'`; default is `'no'` (`Setup.pm:137`), limit
  `misc_limits.mcp_max_result_size` is 500000 (`Setup.pm:317`).
- `templates/webapi/layouts/navbar.html.ep:100` hard-codes `eq 'read-only'`.
- `docs/WritingTests.md:1950-2019` already promises that write operations will
  require a separate setting.
- Unused library features: `scopes`, `auth` hook, `origins`, `instructions`,
  `resource`, `prompt`, `output_schema` / `structured_result`,
  `input_required` (elicitation).
- Installed perl-MCP is 0.15 and provides all of the above. `cpanfile:56` and
  `dependencies.yaml:190` declare `>= 0.80.0`, which 0.15 does not satisfy;
  align the requirement to the version that introduces scopes, the auth hook
  and `input_required`.
- `t/api/17-mcp.t:35-44` carries a legacy subtest that only runs for MCP < 0.15
  (`initialize_session`, `MCP::Server::Legacy`). Legacy clients are not a
  target: drop that subtest and the legacy compatibility path.

## Design decisions

1. **Reuse the existing API controllers, do not reimplement.** Triggering jobs,
   scheduling ISOs, comments, priority etc. already exist under
   `OpenQA::WebAPI::Controller::API::V1::*`. Calling them keeps validation,
   gru/minion tasks, scheduler wakeup, `openqa_*` events, audit logging and
   permission semantics. Duplicating that logic in MCP tools is the main
   maintenance risk to avoid.
2. **Gate write tools by openQA roles.** Config enables the feature; the
   caller's role decides which tools they see. Use the library's `scopes`
   mechanism fed from the authenticated user. The role→scope mapping is
   hard-coded in 127; making it configurable is 128.
3. **Explicit config values, no `mcp_enabled = true`.** `true` is ambiguous and
   would silently enable write access for deployments that upgrade. Use an
   enum validated at startup.
4. **Confirmation for destructive calls** via `input_required` elicitation with
   a sealed state. opencode (primary target client) implements
   `elicitation/create`; an explicit `confirm` argument is the fallback.
5. **No legacy MCP support.** Do not keep the pre-0.15 handshake path.

## Config

```ini
[global]
mcp_enabled = read-write    # no | read-only | read-write
mcp_origins =               # allowed Origin header values (DNS-rebinding guard)
```

- `OpenQA::Setup::load_plugins` becomes
  `$server->plugin(MCP => {mode => $mode}) if $mode ne 'no'`, and dies on an
  unknown value. `register($self, $app, $config)` already receives the config
  hash.
- **`auth/method = None` and `no_localhost_auth` are allowed with
  `read-write`.** With `None`, `OpenQA::Shared::Controller::Auth::_auth`
  resolves the `DEFAULT_ADMIN` user, so MCP gets the same admin privileges the
  REST API already grants on that instance. `no_localhost_auth` is only
  consulted by `Auth#check` (`lib/OpenQA/Scheduler.pm:38`,
  `lib/OpenQA/WebSockets.pm:36`), not by `Auth#auth`, so MCP requests still
  need a Bearer token or API key. Nothing to change: if the admin has decided
  the instance is local/trusted, MCP write is no more permissive than the API.
  Document that `read-write` on an instance with `None`/`no_localhost_auth` is
  a deliberate admin decision.
- `mcp_origins` is worth setting once write mode exists, since browser-based
  MCP clients can be attacked via DNS rebinding on a localhost-bound server.

## Scopes plumbing

```perl
sub register ($self, $app, $config) {
    my $mode = $config->{mode};
    my $mcp = MCP::Server->new->name('openQA')->version('1.0.0');
    # ... tool registration ...
    my $mcp_auth = $app->routes->under('/')->to('Auth#auth')->name('mcp_ensure_user');
    $mcp_auth->any('/mcp' => $mcp->to_action({
        auth => sub ($c) { _auth_scopes($c, $mode) },
        ($config->{origins} ? (origins => [split ' ', $config->{origins}]) : ())}))->name('mcp');
}

sub _auth_scopes ($c, $mode) {
    return undef unless my $user = $c->stash('current_user'){user};
    my @scopes = ('mcp:read');
    if ($mode eq 'read-write') {
        push @scopes, 'mcp:write' if $user->is_operator;
        push @scopes, 'mcp:admin' if $user->is_admin;
    }
    return {scopes => \@scopes, principal => $user->name};
}
```

Write tools declare `scopes => ['mcp:write']`. Effect: `tools/list` hides write
tools from users without the scope, and a call returns 403 with a
`WWW-Authenticate: Bearer …, scope="mcp:write"` challenge. Without the `auth`
hook scopes are not enforced, so this is the security-relevant piece.

## In-process API calls

```perl
sub _api_call ($tool, $namespace, $action, %args) {
    my $c = _get_controller($tool);
    my $user = _get_user($tool);
    die 'insufficient role' unless $user->is_operator;
    my $sub = $c->app->build_controller;
    $sub->stash(current_user => {user => $user}, %{$args{stash}});
    $sub->req->method($args{method});
    $sub->req->url->path($args{path});
    $sub->req->body_params(Mojo::Parameters->new(%{$args{params}}));
    $sub->$action;
    return {code => $sub->res->code, json => $sub->res->json};
}
```

Caveats:

- `OpenQA::Shared::Plugin::SharedHelpers::_current_user` prefers the
  `current_user` stash, so injecting the user works for `current_user`,
  `is_operator`, `is_admin` and `emit_event` (audit `user_id`).
- Route placeholders (`jobid`, `group_id`) are read via `param()`, which checks
  the stash first, so pass them via `stash`.
- Route-level role checks (`Auth#auth_operator`, `Auth#auth_admin`) are
  bypassed, hence the explicit role assertion in `_api_call`.
- `build_controller` has no real transaction, so audit `connection_id` is 0.
  Acceptable; document it.
- Alternative if maintainers prefer full-stack reuse: loopback request via
  `$c->ua->server->app($app)` forwarding the `Authorization` header. Costs a
  local HTTP round trip and a loopback daemon per worker, but keeps route-level
  auth and CSRF semantics. Prefer `build_controller` first.

## Read tools to add (current gaps)

| Tool | Reuses | Notes |
| --- | --- | --- |
| `openqa_list_jobs` | `API::V1::Job#list` | filters: `group_id`, `name`, `state`, `result`, `latest`, `scope`, `limit`; the biggest gap today |
| `openqa_list_job_groups` | `job_group#list` | |
| `openqa_job_group_overview` | `job_group#build_results` | |
| `openqa_list_workers` | `Workers` stats | |
| `openqa_list_assets` | `asset#status_json` | |
| `openqa_get_comments` | `comment#list` | job / group / parent group |
| `openqa_search` | `API::V1::Search` | |
| `openqa_list_products` / `openqa_list_machines` / `openqa_list_test_suites` / `openqa_list_job_templates` | `table`, `job_template#list` | |
| `openqa_get_needle` | `file#needle_json_by_id` | |
| `openqa_list_api_routes` | `routes#list` | self-discovery for LLMs |

All new tools use `output_schema` + `structured_result` instead of the current
plain-text templates: machine-readable and cheaper in tokens. Existing text
tools stay unchanged to not break current clients. Cap results with
`mcp_max_result_size` and `search_results_limit`.

## Write tools (operator tier)

| Tool | Endpoint reused | Annotations |
| --- | --- | --- |
| `openqa_trigger_job` | `POST /api/v1/jobs` | `idempotentHint => 0`; clone-from-job (`_FROM` + setting overrides), the `openqa-clone-job` equivalent; returns new job ids |
| `openqa_restart_job` | `POST /api/v1/jobs/<id>/restart` | `idempotentHint => 0` |
| `openqa_duplicate_job` | `POST /api/v1/jobs/<id>/duplicate` | `idempotentHint => 0` |
| `openqa_cancel_job` | `POST /api/v1/jobs/<id>/cancel` | `destructiveHint => 1`, confirmation required |
| `openqa_set_job_priority` | `POST /api/v1/jobs/<id>/prio` | `idempotentHint => 1` |
| `openqa_post_comment` | `POST /api/v1/jobs/<id>/comments` | API allows any logged-in user, so the role floor here is user, not operator |
| `openqa_schedule_iso` | `POST /api/v1/isos` | `openWorldHint => 1`; expose `validate_create_parameters` as `validate_only` |

Admin-tier tools (job templates, job groups, product/machine/test-suite CRUD,
asset/needle delete, worker kill) are planned in 128. Do not expose user
deletion at all: no confirmation flow makes it safe.

## Confirmation for destructive calls

```perl
sub tool_cancel_job ($tool, $args) {
    my $state = $tool->context->request_state;
    return $tool->input_required({confirm => {method => 'elicitation/create', params => {
        message => 'Cancel job 42 (opensuse-DVD-x86_64-Build42)?',
        requestedSchema => {type => 'object', properties => {ok => {type => 'boolean'}}}}}},
        {job_id => $args->{job_id}})
      unless $state && $state->{confirm}{ok};
    return _api_call($tool, 'API::V1::Job', 'cancel', ...);
}
```

`seal_state` binds the state to the primitive, principal and a 300 s timeout, so
a retry cannot be replayed by a different user. opencode implements
`elicitation/create`; clients without the capability pass `confirm => true`
explicitly. Document both.

## Server-level additions

- `MCP::Server->instructions` — short guidance: role model, limits, how to find
  jobs, that write tools require operator.
- `resource` templates, e.g. `openqa://jobs/{id}/logs/{name}` and
  `openqa://jobs/{id}/settings` — cheaper than tools for repeated reads.
- `prompt`s: `openqa_triage_job`, `openqa_analyze_group_overview` — encode the
  human triage workflow.

## Safety / operational

- Every write call must land in the audit log. Reusing controllers emits
  `openqa_*` events with the user id; add an `mcp` marker to `event_data` so
  the audit UI and the rate limiter (128) can filter.
- Bearer personal access tokens only work over HTTPS or localhost
  (`_token_auth`). API-key signature auth hashes only the URL, not the POST
  body, so it is not usable for MCP calls. Document that write mode requires a
  personal access token over HTTPS.
- CSRF: session-based POST needs a valid token; Bearer/API-key clients are
  exempt via `is_api_request`. Document.
- Validate `limit`/`count` arguments on read tools against
  `search_results_limit`; validate settings on `openqa_trigger_job` so a single
  tool call cannot schedule an unbounded number of jobs.

## UI / docs

- `templates/webapi/layouts/navbar.html.ep`: `config->{global}{mcp_enabled} ne
  'no'`.
- `templates/webapi/admin/mcp_help.html.ep`: show the enabled mode, the enabled
  tools, role requirements, and the client config example. Add the opencode
  form:

  ```json
  {"mcp": {"openqa": {"type": "remote", "url": "http://127.0.0.1:9526/mcp",
    "headers": {"Authorization": "Bearer USER:KEY:SECRET"}}}}
  ```

- `docs/WritingTests.md` MCP section: document `read-write`, scopes, role
  mapping, confirmation flow, token requirements.

## Tests

- `t/api/17-mcp.t`: drop the legacy subtest; add subtests for scope visibility
  in `tools/list` (operator vs. non-operator) and 403 `insufficient_scope`.
- New `t/api/18-mcp_write.t` with `t/data/18-mcp/openqa.ini`
  (`mcp_enabled = read-write`) and fixtures `01-jobs.pl 02-workers.pl
  03-users.pl`:
  - trigger job → new job ids + audit event `job_create` with the right user
  - restart / duplicate / cancel / prio
  - comment create
  - ISO scheduling with `validate_only`
  - role gating: operator can trigger, non-operator cannot
  - elicitation round trip and `confirm` argument fallback
  - `read-write` with `auth/method = None` resolves admin scopes
- `t/ui/05-auth_mcp.t`: navbar entry for `read-write`.
- Unit test for `_auth_scopes` role → scope mapping.
- `COVERAGE=1 make test-unit-and-integration TESTS=t/api/18-mcp_write.t` then
  `make check-line-coverage`; `make tidy`, `make test-checkstyle`,
  `make test-gitlint`.

## Atomic commits

1. `fix(deps): align MCP requirement with the version providing scopes`
2. `feat(config): extend mcp_enabled to read-write with startup validation`
3. `feat(mcp): derive scopes from the authenticated user via the auth hook`
4. `feat(mcp): call API controllers in-process for MCP tools`
5. `feat(mcp): add read tools for jobs, groups, workers, comments and search`
6. `feat(mcp): add job write tools`
7. `feat(mcp): add comment and ISO scheduling write tools`
8. `feat(mcp): require confirmation for destructive tools`
9. `feat(mcp): add resources, prompts and server instructions`
10. `feat(ui): show MCP help for any enabled mode`
11. `docs(mcp): document read-write mode`

## Open questions

- Does `openqa_trigger_job` need `_GROUP` override support (to avoid polluting
  build results), and should it be restricted to non-production groups by
  config?
- Structured results for the 3 existing tools: switch now (breaking) or keep
  text? Recommendation: keep text, add structured output only for new tools.

## Implementation status

Implemented on `feature/127_mcp_read_write_mode`: all 11 commits above, plus
`refactor(mcp): register tools from one table`,
`fix(deps): regenerate spec from dependencies.yaml`,
`test(mcp): drop legacy session subtest`,
`test(mcp): cover controller exception path`,
`test(mcp): cover default admin scopes`.

Deviations from the plan:

- Read tools also cover products, machines, test suites, job templates, assets
  and needles; `openqa_get_needle` reads the needle file from the needle
  directory because the API route serves a static file.
- `openqa_schedule_iso` has no `validate_only`: `Iso#validate_create_parameters`
  is an internal helper with no route, so there is nothing to expose.
- Confirmation is implemented as `input_required` with a `confirm` input request
  (the library's own shape), not the `method => 'elicitation/create'` params
  sketch in the plan.
- Tools are registered from one `%TOOLS` table with `mode`/`scopes`/`call`, so
  the help page and the registration loop share the same source.
- Route placeholders go to both the stash and `mojo.captures`; `param()` reads
  the latter.
- No `mcp` marker in audit `event_data`: the marker exists to serve the rate
  limiter, which is in 128, and adding it would mean touching every controller
  that emits an event. Audit events already carry the user id and the MCP
  connection id.
