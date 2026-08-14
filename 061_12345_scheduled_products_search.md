# Plan: Add support for URL-based search and `settings` search in Scheduled Products log

## Motivation
The user requested the ability to search for values (specifically URLs, like `git:`) via a query parameter `?q=` in the Scheduled products log (`/admin/productlog`), and asked for a help popover explaining this functionality similar to `/tests`.

## Steps
1. **Frontend (JS)**: In `assets/javascripts/audit_log.js`, modify `loadProductLogTable` to parse the `q` query parameter and pass it to DataTables initialization (`search: { search: q || '' }`).
2. **Backend (Controller)**: In `lib/OpenQA/WebAPI/Controller/Admin/AuditLog.pm`, update `productlog_ajax` to cast the `settings` column to text so that it can be searched via the `search[value]` condition: `'CAST(me.settings AS text)' => \%condition`.
3. **Template (UI)**: In `templates/webapi/admin/audit_log/productlog.html.ep`, add a `<span class="search-popover">` with a `help_popover` explaining the search functionality (including the `q` parameter and the ability to search settings). Also fix a minor pre-existing typo (`= id="..."`) in the template.
4. **Testing**: Add a new `subtest` in `t/ui/17-product-log.t` to visit `/admin/productlog?q=FOO`, wait for the AJAX table load, and verify that the search box is pre-filled and results are filtered.
