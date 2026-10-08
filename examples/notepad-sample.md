# A day in the notepad

An illustrative morning, based on the pilot with details made generic. The human asks for two features. Claude
builds one and Antigravity builds the other at the same time. Codex reviews both. One PR comes back.

## What happened

| Time | Who | What |
|---|---|---|
| 09:02 | **human → claude** | Asks for a CSV export and an activity log, in parallel. |
| 09:15 | **claude → agy** | Assigns the CSV export: spec file, branch, worktree. |
| 09:16 | **agy**, **claude** | Both claim their files, which don't overlap: agy the export, claude the activity log. |
| 09:58 | **claude → agy** | Nudge: agy has been exploring for 40 minutes; time to write the tests. |
| 10:14 | **agy → claude** | Handoff: export done, 14 tests, full suite green. Left a marked hook for the lead. |
| 10:31 | **claude → agy** | Review: three things to fix on the same branch. |
| 10:52 | **agy → claude** | All three fixed in one commit. |
| 11:05 | **claude → codex** | Asks for a read-only review of both branches. |
| 11:16 | **codex → claude** | Three real bugs the lead missed, one serious. |
| 11:40 | **claude → all** | Both features merged into one branch, bugs fixed with tests, PR open. |
| 11:41 | **claude → human** | "PR ready, say merge when you've looked." |

## The raw file

This is what `.collab/notepad.md` looks like. Every line is written by `scripts/collab.sh`; nobody edits it by hand.
Format: `time | from → to | KIND | text`, where KIND is `MSG`, `CLAIM`, `RELEASE` or `HANDOFF`.

```text
2026-10-07 09:02 | human → claude | MSG     | Next: CSV export of customers + an activity log. Run them in parallel.
2026-10-07 09:15 | claude → agy   | MSG     | TASK: CSV export per docs/tasks/2026-10-07-csv-export.md,
                                               worktree ../app-wt-agy, branch feat/csv-export.
                                               Only the files in the spec. Commit, no push; handoff to claude.
2026-10-07 09:16 | agy → all      | CLAIM   | feat/csv-export · src/export/*, tests/export/*, src/app/settings/page.tsx
2026-10-07 09:16 | claude → all   | CLAIM   | feat/activity-log (main checkout) · src/audit/*, src/app/activity/*
2026-10-07 09:58 | claude → agy   | MSG     | You've explored enough. Write the failing tests from the spec now, use file tools.
2026-10-07 10:14 | agy → claude   | HANDOFF | feat/csv-export · export + 14 tests, full suite 812 pass, typecheck clean (a1b2c3d)
                                               · left // HOOK: audit export (wired by lead) in route.ts
2026-10-07 10:14 | agy → all      | RELEASE | CSV export done
2026-10-07 10:31 | claude → agy   | MSG     | Review: 3 points. Lock the row while exporting; unknown customer id → 404 + test;
                                               JSDoc on the formula guard. Same branch.
2026-10-07 10:52 | agy → claude   | HANDOFF | feat/csv-export · all 3 fixed in one commit (e4f5a6b), 819 pass
2026-10-07 11:05 | claude → codex | MSG     | Read-only review of main...feat/csv-export and main...feat/activity-log
2026-10-07 11:16 | codex → claude | MSG     | 3 findings: formula guard bypassed by leading spaces (high);
                                               audit entry written when withdraw deleted nothing;
                                               audit entry for unknown document delete
2026-10-07 11:40 | claude → all   | RELEASE | Both branches integrated; Codex findings fixed with tests; 826 pass. PR #48 open.
2026-10-07 11:41 | claude → human | MSG     | PR #48 ready: CSV export + activity log. No migration needed.
                                               Say "merge" when you've looked.
```

*Long entries are wrapped here for reading. In the real file, each entry is one line, and the columns aren't padded.*

## Reading it yourself

```bash
scripts/collab.sh status     # current claims + the latest entry for each agent
scripts/collab.sh read 20    # the last 20 entries
```
