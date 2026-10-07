# Lessons from the pilot

Dated notes from a real web-app project (Next.js + Postgres, about 900 tests) where three agents worked together
in October 2026: **Claude Code** (lead), **Antigravity CLI** `agy` (builder, Gemini Flash or its Claude models),
**Codex CLI** (reviewer, on an entry-level ChatGPT plan). Tool behaviour changes quickly. Treat CLI specifics as
"true when written" and re-check them.

## Setting up the agents
1. **Headless agy auto-denies every shell command** without an allow-rule (`~/.gemini/antigravity-cli/settings.json` → `permissions.allow: ["command(<prefix>)"]`).
2. **Chained commands are denied even when each part is allowed** (`a && b`). Good for safety, but builders must be told "one command per call".
3. **File edits need permission too** in headless mode. The rule is `write_file(<absolute path>)`. Grant only the files in the task's spec.
4. **Git worktrees split the notepad.** A script that resolves "repo root" from its own location writes a separate notepad per worktree. Fix: resolve via `git rev-parse --path-format=absolute --git-common-dir`.
5. **Stale instruction files mislead agents silently.** An old `GEMINI.md` (auto-loaded) described a schema and storage setup that no longer existed. Audit every auto-loaded file: `AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, `.agent/rules/`.
6. **One file, different readers.** `AGENTS.md` held terse-style rules meant for one agent; importing it into the lead's instructions would have changed the lead's style. Keep style rules per agent; share only the protocol.
7. **Headless agy ended its session while waiting on a background task** it had started (a test run). Tell builders to run commands in the foreground.
8. **Asking an agent about itself** made it try to run a command, which was denied. Prefix such questions with "do not use any tools".
9. **Model choice matters more than the vendor.** One older "Pro" model fell clearly behind; a current "Flash" model was the better default, with the builder's Claude models for harder tasks.
10. **Subscription limits shape roles.** The tool with the most generous plan does the heavy building; the one on a small plan does short reviews.
11. **Verify plan claims empirically.** Sources disagreed on whether an entry-level ChatGPT plan allows the Codex CLI. A one-line `codex exec "reply OK"` settled it (it did).
12. **Transient vendor errors happen.** agy once failed with a `403 … cannot determine your account's location`, marked non-retryable; a minute later it worked. Probe with a one-line call and retry before giving up.
13. **Interactive beats headless for Antigravity.** Headless mode needed per-file write rules, ended early on background tasks, and once hit a sign-in error. The normal interactive `agy` inside **tmux** (`send-keys` to type, `capture-pane` to read) worked first time: real sign-in, and ordinary permission prompts the lead can answer. The human can watch live with `tmux attach`.
14. **A watcher loop wakes the lead.** Poll the tmux screen every 15 s for a permission prompt and the notepad for a new HANDOFF. Cheap, and it needs no API.

## The review loop
15. **The review loop works across vendors.** Lead review → feedback via notepad + tmux nudge → builder fixed all 3 points in one commit → Codex independent read-only review → lead runs the full suite → PR.
16. **Capture Codex's verdict properly.** Piping `codex exec` through `head` cut off its final message. Use `codex exec -o <file>` instead of re-running on a limited plan.
17. **Agents pick up the human's quirks from shared files.** Both other agents started replies with the owner's name, because the lead's instruction file said to. Decide which preferences are lead-only.
18. **Pilot timing:** spec → merge-ready PR in about 30 minutes of agent time, once setup issues were fixed. The first three builder attempts failed purely on tooling (permissions, notepad path, auth), never on code.

## Parallel work
19. **Real parallel work happened.** The builder built a CSV export in its worktree while the lead built an audit log in the main checkout. Claims kept them apart: the lead put its page somewhere new instead of editing the page the builder had claimed, and linked it at integration.
20. **The builder over-explores until nudged:** about 25 minutes of read-only `ls`/`find`/`grep` before writing anything. One nudge ("you've explored enough, write the failing tests now, use file tools") and the feature landed in about 15 minutes.
21. **Chain-aware auto-approval.** Approve only when every part of a `&&`/`||`/`;` chain is a safe read-only command. Pipes, redirects, backticks or `$(…)` stop for a human decision. Log every approval.
22. **The builder switched itself to "accept edits" mode** mid-task. Acceptable in an isolated worktree, because the review checks that the commit touched only the spec's file list (it did: exactly 11 files).
23. **Leave a marked seam for integration.** The spec told the builder to put `// HOOK: … (wired by lead)` where the cross-feature call goes. Integration was a one-line replacement.
24. **The cross-vendor review found what the lead missed.** Codex flagged 3 real bugs the lead's review didn't catch: a CSV formula-injection guard bypassed by leading spaces, and two audit entries written when nothing was deleted. Different model families catch different things.
25. **The lead's review caught what the builder missed:** a client component that took the whole translation dictionary as a prop (shipped to the browser), and a money-maths edge case.

## Refactors and specs
26. **"Zero visible change" refactors need exact-text tests written from the old version** (`git show main:<file>`). The builder's tests passed while one line of a greeting silently disappeared; only reading the diff caught it.
27. **Builders over-generalise defaults.** One feature's "off in production" rule was copied onto every new switch, and the tests enshrined it. Review semantics, not just green tests.
28. **Spec gap, not agent gap.** Browser code read a config that only existed on the server. The lead should state the runtime boundary (server / browser / build time) in every spec.
29. **A guard test is cheap** (e.g. "no customer-specific text outside `src/customers/`") and catches what reviewers miss. Codex still found one string the guard's word list didn't cover, so extend the list when that happens.
30. **Interactive builder + watcher, measured:** about 1.5 h for a refactor, 3 approvals logged, no nudges after the first. The handoff arrived exactly as the protocol says.
31. **Scripts that regex-parse CLI output break when the agent's shell sets `FORCE_COLOR`** (ANSI codes inside the text). Run with `NO_COLOR=1` or strip ANSI codes.

## Two agents, one file
32. **Two agents on one file works if one writes the code and the other writes only the tests.** The builder's spec forbade source changes, so the merge was conflict-free.
33. **The builder's test became the harness for the lead's feature.** After merging, the lead added 2 integration cases to the builder's fake-camera test in minutes. Ask builders for reusable fakes, not just passing cases.
34. **A tight spec removes over-exploration:** exact file, exact mocks, numbered cases, "3 runs in a row". The builder finished in ~40 min with zero nudges.
35. **Codex again found a real gap the lead missed** (an uncounted failure path) for a few cents. Keep the independent review even on small features.

## Hardening round (audit → triage → fix, in parallel)
36. **Auto-approver bug: never hard-code an option number.** The watcher always pressed "2" assuming "2 = always allow", but some prompts are only "1 Yes / 2 No". It silently *declined* a coverage run and the builder sat idle. Read the option text.
37. **Codex as a read-only auditor before fixing:** one prompt (8 concerns, "quote the line, give a concrete failing input, max 25 findings") gave 11 findings, all real, in ~10 min. Triage is the lead's job: 1 waited on the human, 1 was accepted with a reason, 9 were fixed.
38. **Check production config before "fail closed" fixes.** The audit's top finding was right in principle, but fixing it straight away would have broken a keepalive job, because the secret it relies on was never set. The lead checks the environment (variable names only), not just the code.
39. **Independent review catches the lead too.** Codex reviewing the lead's own fix found a test that claimed more than it checked.
40. **A builder timing its runs while the lead also runs the suite reports inflated numbers** (815 s vs ~4 min alone). Size CI timeouts from a clean run.
41. **`git push` sometimes returns "Internal Server Error".** A retry loop that verifies with `git ls-remote` beats chaining `push && gh pr create`: the chain aborted and the notepad got a premature RELEASE.

## Publishing this kit
42. **macOS `sed` doesn't turn `\n` into a newline in replacements.** The pilot's watcher split command chains with `sed 's/&&/\n/g'`. On macOS, `ls && rm -rf x` became one string starting with `ls` and would have been auto-approved. It never happened (every approval was logged), but the tests written for this public version caught it on the first run. Test your safety code on the OS you run it on; CI here runs on macOS and Linux.
