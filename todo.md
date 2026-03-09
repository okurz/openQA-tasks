_Note:_ Not appearing numbers mean already done tasks, moved to
tasks/completed/

_Howto:_ For every numbered task create an according implementation planning
document in tasks/ in a numbered fashion, e.g. "11. my task" ->
"tasks/011_my_task.md" and inform the user. Do not execute the plan without
confirmation.

30. *DONE* Offer each user to delete their user details on an openQA instance.
    As we track users in places like the audit log we should anonymize user
    entries there and remove when there is data that is only relevant for this
    user, e.g. api keys
31. *REVIEW* We store some limited user data. Create a privacy policy
    following usual industry best practices for a privacy policy
32. *PLANNED* Provide a way to authenticate using SSH keys instead of API
    key+secret
33. *PLANNED*
34. *PLANNED*
35. follow-up to task 30: we re-use the "api keys" page for users to request
    deleting their data so abusing the page with not fitting name. We should
    either rename the page title, URL, description and according references or
    split out the user deletion and potential future extensions into a
    separate page. Also consider task 32 "authenticate using SSH keys" also
    needing a place where users can manage their public SSH keys.  Proposal:
    Rename "Appearance" into "Profile" and move the deletion dialog there,
    possibly also merging api keys and ssh keys
36. *REVIEW* Within the Perl ecosystem it is a common practice to split tests
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
37. *REVIEW* Is there a new version of bootstrap that we should migrate to?
    Does it refresh our design? Or are there alternative approaches to
    consider to make openQA look more modern?
38. *PLANNED* We prefer Mojolicious style function signatures. We already use
    that in many places. Look up all places left and convert files one by one
    with good verification for each package (file) before continuing. Compare
    to os-autoinst commit 264fcd83 or corresponding PR
    https://github.com/os-autoinst/os-autoinst/pull/1696
41. Ensure documents are wrapped consistently at 80 characters (or 120
    characters as applicable), e.g. all .asciidoc in docs and Readme.asciidoc
