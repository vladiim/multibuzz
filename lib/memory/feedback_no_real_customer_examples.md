---
name: feedback-no-real-customer-examples
description: Never use real customer names, brands, or locations in committed examples (specs, mockups, docs, articles, tests). Make up fictional ones.
metadata:
  type: feedback
---

In any committed artifact that uses illustrative examples — specs, mockups, help articles, docs, seed data, test fixtures, code comments — **do not use real customer business names, brands, or locations.** Invent fictional ones.

The trigger: a Custom Dimensions help article + mockup + spec used `PetResort` and the real PetPro locations Eumundi / Noosa / Sydney as the worked example. PetPro is the user's own company (vlad@petpro360.com.au). The user pushed back: "DO NOT use real examples from petpro! make some up". Replaced with a made-up business: **Acme Outdoors**, locations Portland / Austin / Denver.

**Why:** Real customer/brand/location names in committed examples read as leaking who the customer is and look unprofessional in shared docs. It also couples illustrative copy to one tenant. This sits alongside the CLAUDE.md CRITICAL secrets rule (no account IDs / emails / PII in committed files), but is broader: even non-secret real-world names should be fictional in examples.

**How to apply:** When writing any example, default to an obviously fictional placeholder business (Acme-style) and generic, unrelated locations. Don't mine the real account's data (campaign names, location tags, brands) for "realistic" examples. If the surrounding spec already contains real names (e.g. `spend_dashboard_metadata_breakdown_spec.md` uses `Eumundi-Noosa`), don't propagate them into new files.

Related: CLAUDE.md "CRITICAL Rules" secrets/PII line.
