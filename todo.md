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
    needing a place where users can manage their public SSH keys.
36. Within the Perl ecosystem it is a common practice to split tests into
    dynamic tests in the "t/" folder and author tests in the "xt/" folder. The
    author tests can be excluded from any build environment test calls and
    focus on dynamic tests. A similar change was done in os-autoinst in
    os-autoinst commit 090ad748 in PR
    https://github.com/os-autoinst/os-autoinst/pull/1596
    We already have a Makefile target called "tidy-compile-style" which sounds
    like "author" tests. We should move those tests to the folder xt/, update
    Make rules accordingly and ensure that our upstream CI system circleCI
    still calls all checks and tests applicable. Within our OBS package build
    instructions in dist/rpm/ we can leave out all author tests consistently
