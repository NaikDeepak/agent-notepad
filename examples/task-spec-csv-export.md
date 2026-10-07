# Task: CSV export of the customer list

**Assigned to:** agy  **Lead / reviewer:** claude  **Second review:** codex (read-only)
**Branch:** `feat/csv-export`  **Worktree:** `../app-wt-agy`

## Goal
An admin can download all customers as a CSV from Settings and open it safely in Excel or Google Sheets.

## Files you may touch (nothing else)
- `src/export/customers-csv.ts` (new): pure function `toCsv(rows) → string`
- `src/app/api/export/customers/route.ts` (new): GET, admin session required
- `src/app/settings/page.tsx`: add one "Download CSV" link
- `tests/export/customers-csv.test.ts`, `tests/api/export-customers.test.ts` (new)

## Runtime boundary
`toCsv` is pure and server-only. The route runs on the server. The settings page only renders a link; no data
is fetched in the browser.

## Test cases (write first, see them fail, then implement)
1. Header row + one row per customer, in a stable order (created date, then id).
2. Commas, quotes and newlines inside a field are quoted and escaped (RFC 4180).
3. **Formula injection:** a field starting with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'`, **including after leading spaces**.
4. Empty list → header only.
5. Route: no session → 401; non-admin → 403; admin → 200, `text/csv`, `Content-Disposition: attachment`.
6. Unknown query parameters are ignored, not echoed.

## Seams
In the route, after a successful export, leave exactly `// HOOK: audit export (wired by lead)`; the lead's
activity-log branch wires it.

## Done when
- [ ] Cases 1–6 pass; full suite passes 3 runs in a row; typecheck clean.
- [ ] One commit on `feat/csv-export` (no push).
- [ ] `scripts/collab.sh handoff agy claude "feat/csv-export · <done> · <test result> · <anything unsure>"`
- [ ] `scripts/collab.sh release agy "<note>"`

## Don'ts
No new dependencies. No changes outside the file list. No background commands. One command per call.
