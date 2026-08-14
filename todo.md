_Note:_ Not appearing numbers mean already done tasks, moved to
tasks/completed/

_Howto:_ For every numbered task create an according implementation planning
document in tasks/ in a numbered fashion, e.g. "11. my task" ->
"tasks/011_my_task.md" and inform the user. Do not execute the plan without
confirmation.

30. _DONE_ Offer each user to delete their user details on an openQA instance.
    As we track users in places like the audit log we should anonymize user
    entries there and remove when there is data that is only relevant for this
    user, e.g. api keys
31. _REVIEW_ We store some limited user data. Create a privacy policy
    following usual industry best practices for a privacy policy
32. _PLANNED_ Provide a way to authenticate using SSH keys instead of API
    key+secret
33. _PLANNED_
34. _PLANNED_
35. follow-up to task 30: we re-use the "api keys" page for users to request
    deleting their data so abusing the page with not fitting name. We should
    either rename the page title, URL, description and according references or
    split out the user deletion and potential future extensions into a
    separate page. Also consider task 32 "authenticate using SSH keys" also
    needing a place where users can manage their public SSH keys. Proposal:
    Rename "Appearance" into "Profile" and move the deletion dialog there,
    possibly also merging api keys and ssh keys
36. _REVIEW_ Within the Perl ecosystem it is a common practice to split tests
    into dynamic tests in the "t/" folder and author tests in the "xt/"
    folder. The author tests can be excluded from any build environment test
    calls and focus on dynamic tests. A similar change was done in os-autoinst
    in os-autoinst commit 090ad748 in PR
    https://github.com/os-autoinst/os-autoinst/pull/1596 We already have a
    Makefile target called "tidy-compile-style" which sounds like "author"
    tests. We should move those tests to the folder xt/, update Make rules
    accordingly and ensure that our upstream CI system circleCI still calls
    all checks and tests applicable. Within our OBS package build instructions
    in dist/rpm/ we can leave out all author tests consistently
37. _REVIEW_ Is there a new version of bootstrap that we should migrate to?
    Does it refresh our design? Or are there alternative approaches to
    consider to make openQA look more modern?
38. _PLANNED_ We prefer Mojolicious style function signatures. We already use
    that in many places. Look up all places left and convert files one by one
    with good verification for each package (file) before continuing. Compare
    to os-autoinst commit 264fcd83 or corresponding PR
    https://github.com/os-autoinst/os-autoinst/pull/1696
39. Ensure documents are wrapped consistently at 80 characters (or 120
    characters as applicable), e.g. all .asciidoc in docs and Readme.asciidoc
40. Implement python style checks with ruff+ty from qem-bot instead of (just)
    black
41. Convert all .asciidoc to .md like
    https://github.com/os-autoinst/os-autoinst/pull/2813 for os-autoinst
42. _DONE_ Deduplicate .ini and Setup.pm and config test ->
    https://github.com/os-autoinst/openQA/pull/7111
43. _PLANNED_ central YAML schema for openQA configuration
44. Migrate from assetpack to vite 8 including rolldown which was recently
    released. Reference https://vite.dev/blog/announcing-vite8
45. test-gitlint is called in separate GHA but also as part of the generic
    checkstyle GHA so duplicate. We should consider to exclude gitlint from
    generic checkstyle at best by separating make targets in Makefile already
    and call the according in GHAs
46. https://github.com/os-autoinst/openQA/pull/7132 is a revert of
    https://github.com/os-autoinst/openQA/pull/7120 as all tests showed up as
    "dark blue" so we lost different result colors. Bring back
    https://github.com/os-autoinst/openQA/pull/7120 but fix colors properly.
47. https://github.com/os-autoinst/openQA/pull/7188 is a revert of
    github.com/os-autoinst/openQA/pull/7126 due to all timestamps showing
    "just now". Fix it.
48. _DONE_ In os-autoinst commit e28007f5 I converted all asciidoc files to markdown.
    Now for openQA we should do the same by using well established tools like
    pandoc and as necessary manual fixup, e.g. for more advanced features like
    sub-document inclusions or cross-references. Convert all asciidoc files,
    update references and document conversions and inclusions and tooling,
    e.g. tools/generate-docs tools/generate-documentation
    tools/generate-documentation-genapi, Makefile, .github/checklist.yml,
    dist/rpm/openQA.spec, docs/Gemfile
49. _DONE_ Fix missing coverage in lib/OpenQA/BuildResults.pm reported in #7291
87. /tests/overview shows the number of restarts for tests. Following up on
    that we should allow in the "Filter" box and according URL query
    parameters to filter on "tests restarted more than N times"
95. `openqa-clone-job` supports a reproduce parameter. Extend to optionally
    include the exact worker class combinations so that one can reproduce on
    the very same worker environment on request
101. test developers want to access the remote VNC port and/or SSH of openQA
     SUTs. hints for that are also shown in the openQA webUI interactive mode.
     However this needs direct access to the worker host which is often
     prevented by according network or firewall separation and can also be
     considered unsafe. the openQA webUI should allow operators and admins to
     remote control VNC and SSH to the remote testing SUTs by proxying the
     traffic accordingly in a reliable, easy to reach but also secure way.
102. openQA already reports badges visualizing test and build status. Provide
     a convenient way to copy a Markdown snippet referencing such test or
     build badge, e.g. a copy button on /tests/details with explanation text
