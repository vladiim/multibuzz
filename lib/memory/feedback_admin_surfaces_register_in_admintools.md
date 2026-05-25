---
name: feedback-admin-surfaces-register-in-admintools
description: Every new /admin page must appear as a card on /admin via an AdminTools::ALL entry. Don't ship an admin surface without it.
metadata:
  type: feedback
---

If you add a controller, route, or view under `/admin`, you must also append a `Tool` entry to `AdminTools::ALL` in `app/constants/admin_tools.rb`. The `/admin` dashboard renders this registry as the operator's hub; an unlisted surface effectively doesn't exist for the operator.

**Why:** User shipped the Guided Setups admin (`/admin/guided_setups`) but I didn't add the dashboard card. They had no way to navigate to the surface from the hub and had to type the URL by hand. Strong reaction — "make a note in claude to always add new admin sections here". CLAUDE.md now carries the rule.

**How to apply:** Treat the AdminTools entry as part of the controller-creation diff, not a follow-up. Steps for any new admin section:

1. Add controller + route + views as usual.
2. Open `app/constants/admin_tools.rb`.
3. Pick the right `Categories` constant — `CUSTOMER_SUPPORT`, `PLATFORM_OPERATIONS`, or `DIAGNOSTICS`. Customer-touching operational work is Customer support; flags/dispatches/integrations are Platform operations; metrics/integrity/errors are Diagnostics.
4. Append a `Tool.new(category:, name:, path:, description:)`. Keep the description one short line — what the operator does there, not what the page is.
5. Verify by loading `/admin` and seeing the card.

Don't skip step 5. A passing test isn't proof the operator can find the page.
