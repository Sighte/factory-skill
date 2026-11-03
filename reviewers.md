# Factory review agents

Each reviewer is a separate, **fresh** subagent (`general-purpose`, never `fork`) and
**changes nothing** in the code. It does not know the sealed acceptance tests (only their result as a
number) and does not look for them. It receives from the orchestrator:
- `W` (absolute worktree path) — **all** commands run against `W`, never against the cwd of
  its own shell (which starts in the session folder);
- `M` (checkout of `{{TARGET_BRANCH}}`) and `{{PROJECT_RULES}}`;
- slug and `S` (spec, tasks, `factory-log.md`);
- the diff as the file `$S/review-r<N>.diff` (`git -C "$W" diff origin/{{TARGET_BRANCH}}...HEAD`;
  only committed work counts);
- the test commands from `SKILL.md` ("Commands", without acceptance) with `W` filled in;
- `L` (lock path): full suite only via the queue (`SKILL.md`, "Parallel operation");
- `P` (port of this run's preview, if there is one) and the IDs of the test data;
- the result of the full suite and of the acceptance tests (as a number);
- its open findings from the previous round with IDs, and its checklist below (plus the
  `*_EXTRA` items from `factory.config.md`).

The yardstick is `{{PROJECT_RULES}}` — invariants and user decisions there are settled. That
`/factory` pushes directly to `{{TARGET_BRANCH}}` after the review loop is one such
decision and not a finding. `{{SECRETS_RULES}}`.
**Only look at the shared instance `{{SHARED_INSTANCE}}`:** `{{SHARED_INSTANCE_DONTS}}`.
Logout, delete and write tests only in the preview `:$P`.

## Response format (the same for all, verbatim)

```
VERDICT: APPROVED | CHANGES_REQUESTED
FINDINGS:
- <ID> [blocker|major|minor] <file>:<line> | <problem in one sentence> | <concrete fix> | <evidence: test output, screenshot path, code line>
RESOLVED: <IDs from the previous round that are now fixed>
```

- **IDs:** prefix per reviewer (`RT-` runtime, `SEC-`, `DEP-`, `UI-`) + sequential number. A
  finding from the previous round that is still open keeps its ID — that is how the loop recognizes
  recurring issues.
- `blocker`: function broken, security hole, data loss, quality loss in real operation.
- `major`: clear defect that must be fixed before the push.
- `minor`: improvement, does not block, goes into the report.
- `APPROVED` means: no open `blocker`/`major`. No finding without evidence.
- A finding against a user decision in `{{PROJECT_RULES}}` is at most `minor`
  with the note "user decision".

## Responsibility (orchestrator, from `git -C "$W" diff --name-only origin/{{TARGET_BRANCH}}...HEAD`)

| Reviewer | responsible if a changed file matches |
|---|---|
| Security (§2) | `{{REVIEW_SECURITY}}` — default always, except tier S: there the UI/UX reviewer also checks §2 item 6 (frontend) |
| Runtime (§1) | `{{REVIEW_RUNTIME}}` — what counts is what actually goes into the shipped artifact (e.g. the current `.dockerignore`), not an enumeration |
| UI/UX full (§4) | `{{REVIEW_UI}}` |
| UI/UX text only (§4.5) | otherwise: `{{REVIEW_UI_TEXT}}` |
| Dependencies, follow-up check (§3) | diff touches files that do not appear in `tasks.md` — only for these files |

---

## 1. Runtime reviewer — "no quality loss in real operation"

For everything that goes into a shipped artifact (container image, binary, worker,
app build). If `{{REVIEW_RUNTIME}}` is missing, this reviewer is dropped.

1. **Baseline comparison.** The pass/fail list of the base state is in
   `$S/baseline-tests.txt` (created once by the orchestrator). Run `{{TEST_FULL_LIST}}` on `W`
   (via the queue), compare the lists: every test that is green there must stay
   green. Regression = `blocker`. (Latency/performance can only be checked via existing threshold tests
   — they count under "green stays green".)
2. **Artifact.** The orchestrator has built `factory-<slug>`. `{{ARTIFACT_IMPORT_CHECK}}` with
   all changed and dependent modules (with a dummy env if a module requires env on
   import). An import/a file that the artifact does not contain (ignore list,
   build context) is a `blocker`.
3. **Core functions** (`{{RUNTIME_CORE_FUNCTIONS}}`), per item: proven by a green test
   **or** justifiably untouched by the diff. If both are missing → `major` with the scenario test that
   must be written. Generically always included:
   - startup, normal operation, clean shutdown (also via SIGTERM), cleanup;
   - multi-step flows (two requests in a row, a request during a
     running response, abort midway);
   - synchronous/blocking I/O is not on the event loop.
4. **Configuration reaches the runtime:** Every new field/every new setting arrives in the artifact on
   **every** startup path (all runner/deploy variants, config fetch at
   boot, live update if needed). "Only saved in the store, never read" is
   `major` — experience shows this is the most common bug class.
5. **Harness comparison** (if `{{HARNESS_DIR}}`): table from `{{HARNESS_COMPARE}}`,
   details per run in the harness logs. Classification:
   - Regression in a scenario: `blocker`.
   - Test plan scenario not 2/2 ok: `major`.
   - "Regression" always means: after re-measuring (6 runs with the change). A
     worse rate over 2 runs is not a finding.
   - No scenario for the changed behavior: `major`, with the scenario that belongs in
     `{{HARNESS_SCENARIO_FILE}}`.
   - Average quality score clearly dropped or latency noticeably increased: `minor`, with
     the numbers.

   Core functions from item 3 that a green scenario covers count as proven.
6. Always include the **live checklist** in the verdict, i.e. what remains to be checked in real operation.
   The harness is a mock. "Guaranteed" means: everything that can be checked locally
   has been checked. The checklist always includes `{{LIVE_CHECKLIST_ALWAYS}}`.
7. `{{RUNTIME_EXTRA}}`

## 2. Security auditor — roles first

First the `security-review` skill on the diff, then this list. The skill needs a
git working directory, but your shell starts in the session folder, and `cd` does not survive the
call: run every git command as `git -C "$W" …` or read the diff file
`$S/review-r<N>.diff`. If the skill still does not run, apply its checkpoints by hand to the
diff file and say so in the verdict.

1. **Role matrix per new or changed route/action**: `{{SECURITY_ROLES}}`. For each
   row, the expected result against code **and** test. Test missing → `major` (give the test as the
   fix).
2. Access to other users' objects only via the project's central authorization point; another user's
   object does not reveal its existence (404 instead of 403, if the project has decided
   so).
3. Auth declaratively on the route (middleware/dependency), not in the body — otherwise the
   framework validates the body first and answers a caller without a token with a
   validation error. Route guard tests green.
4. Tenant separation: no data, numbers or statements of existence about other tenants (not
   even in error messages, counters, previews).
5. External input (mails, uploads, files, webhooks, chat, calendar …): caps, `fullmatch`
   instead of `search`, escaping, regex without backtracking trap, paths (`..`, IDs), prompt injection
   (framed as data).
6. Frontend: no inline scripts, no `style=` attributes (CSP), no `innerHTML` with
   customer data without escaping.
7. Secrets: not in logs, argv, audit, mails or responses.
8. New storage location for personal data → in all deletion/retention paths;
   audit line for permission-relevant changes.
9. **Test infrastructure** (list from the orchestrator, `SKILL.md` "Sealed acceptance tests" rule 6):
   changes to test configuration, global fixtures, skip/xfail markers or
   environment detection ("is a test running?") without a justifying task → `blocker`. Code that behaves
   differently under test than in operation, likewise.
10. `{{SECURITY_EXTRA}}`

## 3. Dependency checker — what else hangs off this?

Two modes:

- **Before the build** (step 2, for tier M/L — S runs have a short plan without a checker):
  reads spec and tasks, traces every function, every field and every route that the change will
  touch through to its last user (grep across the whole repo). Result instead of a verdict:
  ```
  TASKS_ADD:
  - <new task, names the file> | <why: which dependency>
  ASSUMPTIONS_ADD:
  - <open question + chosen default>
  DECISION_POINTS_ADD:
  - <only if one of your assumptions clearly changes the result: question | options, default first>
  PREREQUISITES_ADD:
  - <what must exist outside the code and is missing (configuration, account, token)>
  INTERFACES_MISSING:
  - <requirement without a defined interface in design.md — sealed acceptance tests need it>
  TIER: S | M | L
  REASON: <one sentence: which criterion below is decisive>
  ```
  Empty lists mean: the spec is complete. The orchestrator adds `INTERFACES_MISSING` to
  `design.md`. You rate the **tier** based on spec, tasks **and** your own
  `TASKS_ADD` — the highest applicable line wins, when in doubt the higher one:
  - **L**, if any of these applies: `{{TIER_L}}`
  - **M**, if any of these applies: `{{TIER_M}}`
  - **S**, otherwise: `{{TIER_S}}`
- **Follow-up check** (review loop, per responsibility): the same list, only for the
  files outside `tasks.md`. Answer in the normal verdict format.

1. All callers of changed functions and signatures — including tests, scripts, other modules.
2. New field in the data model: validation, all startup paths of the runtime, public API
   (schema, old clients), templates/defaults, default for existing data (field missing → ?).
3. Configuration/env: where is it set, where passed through, where mirrored.
4. Artifact boundary: does the runtime code import something new that the build does not include?
5. Data protection paths: deletion, retention, opt-out.
6. Mixed versions: does the new server work with old clients/artifacts and
   vice versa (rollout is not atomic)?
7. Frontend: all places that use the field or the route; texts in all languages;
   text guards.
8. Docs and operations: `{{PROJECT_RULES}}` invariants, deploy docs, CI path filters (new
   test files, new artifact paths), lockfiles in sync.
9. Other open OpenSpec changes (`openspec list`) that touch the same files.
10. `{{DEPS_EXTRA}}`

## 4. UI/UX reviewer — attractive and consistent

Load skills first, as far as installed: `taste-skill:redesign-skill` (audit of existing
interfaces), `ui-ux-pro-max:ui-ux-pro-max`, `design:design-critique`,
`design:accessibility-review`, `design:ux-copy`. Style source: `{{STYLE_SOURCE}}` and the
existing components — **newly built things must look as if they had always been there.**
In "text only" mode only item 5 applies.

1. Screenshots with `{{SCREENSHOT_TOOL}}`, per width from `{{SCREEN_WIDTHS}}`:
   before `{{SHARED_INSTANCE}}` (read-only steps), after `http://127.0.0.1:<P>`
   (preview of this run, port from the log). No browser MCP shared by all sessions.
   File names `<slug>-before-<view>-<width>` and `<slug>-after-…` respectively.
   Every changed view, plus empty, loading, error and long-text state (stub data only
   client-side).
2. Visuals: hierarchy, spacing on the grid, alignment, type scale, colors only from tokens,
   hover/focus/active states, subtle transitions (`prefers-reduced-motion`), consistent icons.
   "Looks like a standard template" or "doesn't fit the rest" is a `major`.
3. Mobile: no horizontal scrolling, tap targets ≥ 44 px, nothing cut off.
4. Accessibility: contrast AA, labels, keyboard operation, visible focus.
5. Texts: form of address and terms per `{{PROJECT_RULES}}`, no internals (technology, providers,
   error codes), buttons say what happens; server messages shown in the UI are customer-facing text.
6. Technical: no inline scripts, no `style=` attributes (positions via CSSOM), no
   console errors. For tier S additionally §2 item 6: every customer value in `innerHTML` goes
   through an escape function (prefix stays `UI-`).
7. `{{UI_EXTRA}}`

Findings always with a screenshot path as evidence.

**Screenshot recipes:** If the frontend logic is globally reachable, a step is a
JS expression, e.g. `(async()=>{await openView("<id>");await new Promise(r=>setTimeout(r,1500));
return document.documentElement.scrollWidth})()` — return values appear in the output (good for
`scrollWidth` vs. `innerWidth`). `confirm()` halts a headless run: do not open confirmation
dialogs. Real mouse hover does not exist; check hover rules in the CSS.
