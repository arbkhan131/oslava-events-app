# Privacy, correction and deletion request resource

This file supports R9 readiness and store-review preparation. It must be replaced or configured with the real business-approved privacy contact before production submission.

## In-app path

Workers can open Profile → Privacy and deletion to read the policy summary, view request status and submit an account deletion request for verification.

## External request URL

Google Play requires a public deletion request resource. Use `docs/account-deletion-request.html` as the reviewed static content template, then host it at the production support/privacy domain in R10/R11 after the real contact details are supplied.

Do not publish the placeholder as the final store listing URL. Required production values:

- public request URL
- privacy/support email or form destination
- business owner/contact name if required by store listing
- tested process for matching external requests to the registered phone/Worker ID

## Fulfillment behavior

A self-service request remains `OPEN` with `PENDING_VERIFICATION` until an authorized Admin/Super Admin verifies it. Verified due requests are fulfilled only by Super Admin/service-role jobs. Fulfillment sets the account inactive, invalidates device tokens, clears current profile photo references, queues Storage object deletion, pseudonymizes profile PII and preserves operational/audit records required by the approved retention policy.
