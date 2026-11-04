# Privacy scrub

The repository is public. Before showing the preview, scrub the **title, every section, and any comment**.
Replace each item with a placeholder, then tell the user in one line what kinds of things you replaced (never repeat the values).

| Remove | Looks like | Replace with |
|---|---|---|
| People's names (patients, members, SKs, family) | a full name, "<first name>'s wife" | `<name>` or a role: "the patient", "the SK" |
| Phone numbers (Bangladesh and others) | `01XXXXXXXXX`, `+880 1XXX-XXXXXX`, `8801XXXXXXXXX` | `<phone>` |
| National ID / birth registration numbers (NID) | 10, 13 or 17 digits | `<nid>` |
| Email addresses (real people) | `someone@domain` | `<email>` |
| Member, household, patient or encounter IDs tied to a person | FHIR IDs, UUIDs, household codes | `<member-id>`, `<household-id>`, `<encounter-id>` |
| Location: GPS coordinates, village + house, addresses | `23.7xxx, 90.4xxx`, "house next to the mosque in ..." | `<location>` (keep district/upazila only if it matters for the bug) |
| Clinical details about a real person | "her BP was 170/110 yesterday" | Generalise: "a pregnant patient with a high BP reading" |
| Credentials: passwords, PINs, tokens, API or hash keys, `Bearer ...`, `hf_...`, `ghp_...`, JWTs (`eyJ...`), private keys | any | `<redacted-secret>` - and tell the user to rotate it if it was real |
| Backend URLs with credentials or internal hosts | `https://user:pass@host/...`, internal IPs | `<backend-url>` (public hostnames without credentials are fine) |
| Raw logs (logcat, console, crash dumps) | many lines with IDs/tokens | Keep only the few lines that show the error, after scrubbing every line with this table |
| Usernames of field staff | login IDs | `<username>` |

Keep: app version (`1.1.0+15`), dates, device model, Android version, screen names, programme names, error messages with no personal data, counts ("3 households").

**Screenshots and recordings:** you cannot attach them. After the issue is created, the user may add them on GitHub **only** if they use training/test data and show no real patient or member details (names, phone numbers, IDs, faces, locations). Otherwise, describe what is on screen in words.

**Security:** if the scrub finds that the report itself is about leaked data or a vulnerability, stop filing and send the user to the private advisory link in SKILL.md.

Tick the Privacy check box (`- [x]`) in the draft only after the scrub is complete; the user confirms it by approving the preview.
