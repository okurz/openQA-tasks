### Tier 1 — mergeable today, no code work

 ┌───────┬──────────────────────────────────────┬────────────────────────────────────┬───────────────────────────────────────────────────────┐
 │ PR    │ branch                               │ state                              │ open points                                           │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #7953 │ feature/136_poo45671_improve_develop │ CLEAN, 41 pass, 2 approvals        │ Only mergify evaluation. Optional close-out:          │
 │       │ er_mode_hint                         │ (Martchus, Vogtinator), 0 CR       │ perlpunk's 1-line suggestion (exists → definedness)   │
 │       │                                      │                                    │ is not applied in the local branch                    │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #7968 │ feature/allow_always_investigate     │ DIRTY, 41 pass, 2 approvals        │ Rebase + push. No local branch exists — fetch PR      │
 │       │                                      │ (Martchus, ricardobranco777), 0    │ head, rebase, push                                    │
 │       │                                      │ unresolved threads                 │                                                       │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #7914 │ feature/redundant_assets_1           │ CLEAN, 43 pass, 1 approval         │ One more approval (or merge-fast label). Unblocks     │
 │       │                                      │ (Martchus), 0 threads              │ drafts #7915/#7916                                    │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #8027 │ feature/141_less_limited_scheduled_j │ CLEAN, 39 pass, 1 approval, 2      │ Template-literal point is already satisfied in the    │
 │       │ obs_display                          │ threads                            │ PR; only thread resolution + 2nd approval             │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #7960 │ feature/openqa_ecosystem             │ CLEAN, 41 pass, 1 approval, 0      │ 2nd approval                                          │
 │       │                                      │ threads                            │                                                       │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #7989 │ feature/auto_update                  │ CLEAN, 41 pass, 1 open thread      │ 2 approvals; okurz's own note says the jQuery series  │
 │       │                                      │ (perlpunk, answered)               │ should follow this one                                │
 ├───────┼──────────────────────────────────────┼────────────────────────────────────┼───────────────────────────────────────────────────────┤
 │ #7841 │ feature/007_remove_jquery_3_needle   │ CLEAN, 43 pass, 1 approval, 0      │ acceptance-tests-needed label blocks mergify — remove │
 │       │                                      │ threads                            │ it (and honour "after #7989")                         │
 └───────┴──────────────────────────────────────┴────────────────────────────────────┴───────────────────────────────────────────────────────┘

 ### Tier 2 — one small fix and they are in the queue

 - #7964 (feature/worker_host_job_table_2, 6-line change, local content identical to PR head): Martchus's CR asks wait_until_element_gone to
   disable the implicit timeout internally — a small t/lib/OpenQA/Test/Utils.pm refactor; perlpunk already approves.
 - #7935 (132_…_1, local content identical): Martchus explicitly says he is "only not approving as you might want to look into the group-by
   loop" → look, reply, rebase (1 OBS failure).
 - #7762 (perlcritic_probitic_escaped_delimiters): 2 approvals, 0 unresolved; DIRTY + 2 OBS failures. Rebase the PR head, not the local branch
   — the local branch is a 1-commit/3-insert subset vs the PR's 11 files.
 - #7727 / #7775 / #7777: 1 approval, all CI green except 2 OBS failures caused by conflicts; rebase push clears them. #7777 additionally has
   2 unresolved Martchus nitpicks. #7775 and #7727 have no local branch / content-identical local respectively.
 - #7877 (43 pass, 5 open threads, Martchus "only a few nitpicks"), #7849 (46 pass, 4 open threads from foursixnine/perlpunk), #7920 (Martchus
   wants the impact module actually used): realistic in a day if you want the review-churn.
 - Not today: #7991 (Martchus proved UI tests fail without the implicit wait), #7609, #7553 (test + 2 OBS failures), #8034.

 ### Best branches to open new PRs from today (no open PR, clean commits, tests present)

 1. feature/140_openqa_bootstrap_configurable_repos — 5 commits, 27 files, +485/−45, ships
    t/44-scripts-{continuous-update,openqa-bootstrap-container,openqa-bootstrap,openqa-repo-url}.t + fixtures.
 2. feature/poo194513_api_keys — script/openqa-create-api-key + t/44-cli-create-api-key.t (+182), complements the merged #7908.
 3. feature/xterm_console_font_changed + feature/xterm_console_font_changed_1 as one PR — verify_log_quality helper in
    t/lib/OpenQA/Test/Utils.pm, wired into t/full-stack.t and t/33-developer_mode.t, plus font deps in dependencies.yaml/spec/Dockerfile.
 4. feature/117_investigation_tab_extensions — 4 files, +155, t/10-jobs.t + t/ui/18-tests-details.t changes; depends on #7968.
 5. feature/improve_t_37_limit_assets_stability — 1-line test fix (utime(...) call).
 6. feature/fix_leap16_build, feature/apparmor (forbids /usr/bin/ssh breakout in the worker profile), feature/nginx — tiny, packaging/etc;
    apparmor has no in-repo tests, so these will attract checklist comments.
 7. feature/091_197483_abort_results_cleanup_early_low_level_df (+94/−6 incl. 65 lines of t/42-df-based-cleanup.t) — pick this or
    _most_jobs_first (+27/−95), and coordinate with #7777 and Martchus's draft #6924.

 ### Not merge-ready / stale — prune, don't PR

 - Blocked by unmerged parents: feature/122_…_5/_6 (parts after #7877/#7878/#7879/#7880), feature/132_…_2/_3/_4,
   feature/redundant_assets_2/_3, feature/100_…_use_modules (#7711), feature/109_… (#8034, 8 failing checks).
 - WIP with known failing tests: feature/force_result2, feature/force_result_prevent_removing_label_in_update_comment,
   feature/start_db_in_tests_poo102524, feature/t_cache_service_controller_influxdb, feature/enhance_engine, feature/next_old_pre_2026,
   feature/extract_module_dump_templates, feature/fix_developer_t_improvements2, feature/fix_load_check_poo189096,
   experimental-enhance/optimize_less_test_job_modules, experimental-feature/completely_external_schedule_distri_url_explicit,
   feature/multi_host_tokens*.
 - Design decision outstanding: feature/poo205785_only_show_command_collapsed vs …_alternative_2 — two competing logview implementations, no
   tests.
 - Duplicates/stale: feature/gh7010_download_all (the feature landed in master, net diff is 3 blank-line deletions), feature/redundant_assets
   ≡ feature/redundant_assets_3 (identical patch-id), feature/125_poo207879_better_api_key_handling_1 ≡ _3, feature/next vs
   feature/019_poo196913_handle_huge_job_groups_gracefully (#7026 open, patches differ), all no_rebase-*/gh-pages/subrepo/ branches. Keep
   feature/100_migrate_from_assetpack_to_vite_8 PR as canonical (local is 13 commits vs PR's 14).
 - #7913's local branch is a slimmed variant of the PR head (7 insertions vs 8/−1) — rebase the PR head, don't push the local tip.

 Content-identical local↔PR-head rebases (safe to push): #7727, #7777, #7912, #7877, #7935, #7953, #8027, #7841, #7914, #7915, #7916, #7964.
 Content differs: #7762, #7913, #7849, #7843, #7682.

 All of the above actions (force-with-lease pushes to okurz, labels, review requests) are remote writes I have not run. Tell me which
 PRs/branches to push, which labels to add, and whom to request reviews from, and I'll execute that list.
