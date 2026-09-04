# Oslava Events Codex Instructions

The product blueprint and files under /docs are authoritative.

Development rules:

1. Work on only the explicitly requested phase.
2. Do not automatically continue to the next phase.
3. Do not alter finalized business rules without explicit approval.
4. Backend/Supabase is authoritative for:
   - permissions
   - booking
   - capacity
   - conflicts
   - cancellation
   - waitlist
   - category eligibility
5. Flutter must not duplicate security-critical business rules as authority.
6. All database changes must use versioned migrations.
7. Always use `npx supabase`, not global `supabase`.
8. Never run `npx supabase db push` without explicit approval.
9. Never expose service-role keys, database passwords, or server credentials.
10. All exposed Supabase tables must use explicit grants and RLS.
11. Critical mutations must be auditable.
12. Run `flutter analyze` after Flutter changes.
13. Run applicable tests after every phase.
14. Do not modify unrelated files/features.
15. Report changed files, tests run, and outstanding issues when finished.
16. Git commits mark approved working milestones.
