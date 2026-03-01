_Note:_ Not appearing numbers mean already done tasks, moved to
tasks/completed/

_Howto:_ For every numbered task create an according implementation planning
document in tasks/ in a numbered fashion, e.g. "11. my task" ->
"tasks/011_my_task.md" and inform the user. Do not execute the plan without
confirmation.

30. *DONE* Offer each user to delete their user details on an openQA instance. As we
    track users in places like the audit log we should anonymize user entries
    there and remove when there is data that is only relevant for this user,
    e.g. api keys
31. *REVIEW* We store some limited user data. Create a privacy policy following usual
    industry best practices for a privacy policy
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
