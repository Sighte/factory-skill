---
name: factory
description: Spec-driven Software Factory. A feature idea becomes an OpenSpec change; after exactly one approval gate it is built, checked against sealed acceptance tests that the building agent does not know, checked in a review loop, and pushed directly to the target branch. Use for "/factory <idea>", "factory", "build this end to end". Resumes an aborted run if the slug already exists.
---

# /factory "<feature idea>"

Runs the whole chain for **one** idea. Exactly **one** question to the user (approval gate, step 3); otherwise
everything runs through — embedded skills ask no questions either (see steps 2 and 4).

**Project adapter:** All project-specific values (branches, test commands, paths, reviewer
responsibilities, tier criteria, preview, harness) live in the project's `factory.config.md`
(lookup: first `$R/factory.config.md` — outside the worktree, so implementers cannot read `SEALED_ROOT` and `ACCEPTANCE_RUN` —, then `<repo>/.claude/factory.config.md`). In the text below
they appear as `{{SLOT}}`. **If the file or a required slot is missing, stop** and say
which one is missing (template: `factory.config.example.md` next to this file). An empty
optional slot means: the corresponding part is skipped (and that is stated in the report).

Shells — including those of subagents — start in the session folder, and `cd` does not survive
a call. That is why the skill works only with **absolute** paths, which are recorded in the log header
(with `{{PATH_STYLE}} = windows` in Windows format via `pwd -W`):

| | Path |
|---|---|
| `R` | `{{SESSION_ROOT}}` (session folder; contains `M` and the OpenSpec folder) |
| `M` | `$R/{{REPO_DIR}}` — checkout on `{{TARGET_BRANCH}}`, possibly the mount of the shared instance |
| `W` | `{{WORKTREE_PATTERN}}` — worktree of this run |
| `S` | `{{OPENSPEC_DIR}}/changes/<slug>` — spec, tasks, log |
| `L` | `{{LOCK_DIR}}` — locks and queue |
| `Z` | `{{SEALED_ROOT}}/<slug>-<random>` — **sealed acceptance tests** (see "Sealed acceptance tests") |
| `T` | `{{HARNESS_DIR}}` — optional scenario harness (real artifact against a mock) |
| `K` | folder of this `SKILL.md` (for `queue.sh`) |

Always run git as `git -C "$W"` or `git -C "$M"`. If the skill `openspec-propose` is missing, stop
and say that the session must start in `R` (the OpenSpec skills live there).

## Hard rules

- Never `{{PROD_BRANCH}}`, never `{{PROTECTED_JOBS}}`, never an MR/PR to `{{PROD_BRANCH}}` —
  that is a separate release process.
- Push to `{{TARGET_BRANCH}}` only if the tests are green, **the sealed
  acceptance tests are green** (in tiers per `{{ACCEPTANCE_TIERS}}`) **and** in the last
  review round all responsible reviewers reported `APPROVED`.
- Never skip the approval gate, not even for "small" ideas.
- **No agent that writes or checks code for the run knows the acceptance tests** — neither
  their location nor their content (rules in the section "Sealed acceptance tests"). The orchestrator does not read
  them either.
- `{{SECRETS_RULES}}` — do not read or print secrets, no real emails/payments/
  external side effects.
- `M` is **never** modified — other sessions work there. Only exception: the pull after
  the push, and only if nothing is pending there.
- The shared instance `{{SHARED_INSTANCE}}` is **view-only** — for every agent of the
  run: `{{SHARED_INSTANCE_DONTS}}`. Anything that writes or logs out happens only in the run's own
  preview `:$P` (own copy of the data).
- Every state a reviewer is supposed to see is **committed**. Reviewers only see commits.
- Only touch your own resources (names with your own slug, your own port, your own lock).
  Never delete other `factory-*` containers, worktrees, images or locks — only mention them.

## Parallel operation

Several `/factory` runs (and other sessions) run at the same time. Everything that belongs to a run carries
the slug in its name; only the git repo, `origin/{{TARGET_BRANCH}}` and Docker are shared.
Locks live in `$L` (passed to every subagent) and are created with `mkdir` (atomic — fails
if it already exists). **Heartbeat** means: whoever holds a lock or a ticket, or is waiting
for one, runs `touch` on it every minute — for long commands via a background loop:
`( while sleep 60; do touch "$X" 2>/dev/null || break; done ) & HB=$!` … `kill $HB`.

- **Run lock** `$L/run-<slug>/`: prevents two sessions from driving the same run.
  Contains `owner` (start time + random ID; the ID is also in the log header). On every log entry, `touch` the lock.
  Release in step 8, on abort, and on "Abort" at the approval gate. If it already exists: last
  `touch` younger than 90 min → **stop** with "running in another session (last
  sign of life N min ago); if it crashed: `rm -r $L/run-<slug>` and run `/factory` again".
  Older → orphaned, take over (rewrite `owner`, note in the log).
- **Push lock** `$L/push/`: held by exactly one run from "rebase" to "push" (step 7),
  so that runs on `{{TARGET_BRANCH}}` do not pull the base out from under each other. The holder
  keeps the heartbeat the whole time (also while waiting in the queue for the
  tests). Wait **in the background** with `run_in_background`, then wait for the notification
  — no foreground `sleep`. Last `touch` older than 5 min → orphaned, gets
  cleaned up:
  `until mkdir "$L/push" 2>/dev/null; do find "$L" -maxdepth 1 -name push -mmin +5 -exec rmdir {} \; ; sleep 15; done`
  Always release (`rmdir "$L/push"`), also on abort.
- **Queue for heavy jobs** `$L/queue/`: `{{HEAVY_JOBS}}` run across all runs
  **one after another, in order of arrival** — including the acceptance tests if
  `{{ACCEPTANCE_RUN}}` is heavy. Light jobs (`{{TEST_ONE}}`, `{{TEST_LIGHT}}`, preview,
  screenshots) run immediately. Packaged in `$K/queue.sh`, start with
  `run_in_background`: `bash "$K/queue.sh" "$L" <slug>-<job> <output-file> <command …>` — waits, keeps the
  heartbeat, always returns the ticket, shows the last lines, exit code = command.
  The output file lives under `$W/.superpowers/` (gitignored). What the script does —
  subagents follow it too:
  ```bash
  Q="$L/queue"; mkdir -p "$Q"; T=$(date +%s%N)-<slug>-<job>; touch "$Q/$T"
  # wait in the background (run_in_background) until your own ticket is first; meanwhile keep
  # your own ticket fresh and remove tickets with no sign of life for 5 min (crashed)
  until touch "$Q/$T"; find "$Q" -type f -mmin +5 -delete; [ "$(ls "$Q" | sort | head -1)" = "$T" ]; do sleep 10; done
  # … run the job, with a heartbeat on the ticket (X="$Q/$T") …
  rm -f "${Q:?}/${T:?}"   # always, even if the job fails (`:?` — otherwise the rm safety check blocks)
  ```
  Record the wait time in the log ("waiting for queue, position N"). No run holds a
  ticket while waiting for the push lock — return the ticket first, then queue up.
  A `queue.sh` ended via TaskStop leaves its ticket behind (the trap does not fire) →
  delete your own ticket explicitly.
- **Preview port**: first free one from `{{PREVIEW_PORTS}}`, see step 5; recorded in the log.
- **Git locks**: all worktrees share one `.git`. If git reports `index.lock`/`unable to lock ref`,
  wait briefly (background waiting as above) and retry the command once. Never
  delete `.git/*.lock`.
- Screenshots: `{{SCREENSHOT_TOOL}}` picks its own debug port; file names carry the
  slug. Do not use a browser MCP shared by all sessions.

## Log: `$S/factory-log.md`

The single source of truth about the run — context can get summarized, the file cannot.
Header (once, in step 1): idea, slug, `R`, `M`, `W`, `S`, `L`, owner ID of the run lock,
base SHA; after step 2 `Tier` + reason; after step 3b the **manifest** of the
acceptance tests (count + `sha256` per file, **no** path, no content); later `P=<port>`.
The path `Z` is **not** in the log (implementers read `$S`), only in the pointer `{{SEALED_ROOT}}/index/<slug>` (`$L` goes to every subagent, so not there).
After that one line per event, appended **immediately** after the event:

```
| Time | Step | Round | Result | Open finding IDs | Commit |
```

Counters are read from this file, never from memory:
- **Test repair** (step 5): at most 3 attempts **per entry** into step 5.
- **Acceptance repair** (step 5, red acceptance tests): at most 3 attempts **per run**;
  a requirement ID that is still red after two fix attempts → abort.
- **Review rounds** (step 6): at most as many as the tier allows (S: 2, M/L: 5)
  **per run**, also after jumping back from step 7. After an escalation the new limit applies.

## Tiers — how much effort the run gets

A pure presentation change does not need 40 minutes of review. Criteria:
`{{TIER_S}}` / `{{TIER_M}}` / `{{TIER_L}}` (details `reviewers.md` §3). The orchestrator assigns a preliminary tier
in step 2; for M/L the dependency checker decides afterwards. The user sees
the tier at the approval gate and can set it there via "Change". Tier and reason go into the
log header.

| | **S** — presentation/text | **M** — normal | **L** — critical path, permissions, data |
|---|---|---|---|
| Spec | **Short plan** by the orchestrator, no OpenSpec, no dependency checker | Spec agent + dependency checker | Spec agent + dependency checker |
| Acceptance tests | only if `S` is in `{{ACCEPTANCE_TIERS}}` | sealed (step 3b) | sealed (step 3b), also edge cases and roles |
| Build | **one** implementer for all tasks, no SDD task review | SDD per group; task review only for groups with logic (not for pure tests, CSS, CI, texts) | SDD per group, each with task review |
| Full suite | once in step 5 | after groups that change backend code | after every group |
| Review loop | UI/UX only (also checks frontend security), max. 2 rounds | per responsibilities, max. 5 | per responsibilities, max. 5 |
| Models | `{{MODELS}}` | | |

Approval gate, preview, screenshots, push rules and report are the same in every tier.
**Escalating happens automatically, de-escalating never:** If the real diff (step 6.2,
every round) touches something that meets the criteria of a higher tier, the
higher tier applies from that round on, including its reviewers — and, if the new tier requires sealed
acceptance tests and there are none yet, step 3b is done retroactively (the test author gets the spec/short plan,
not the diff). This goes into the log and the report. No spec is written
retroactively; the short plan stays.

## Sealed acceptance tests — the building agent does not know them

Goal: The agent implementing the task should build against the **requirements**, not against
the test. It knows the spec, tasks, test plan headings and interfaces — not the concrete
acceptance tests (inputs, expected values, edge cases). That way it can neither satisfy them specifically
("teaching to the test") nor weaken, skip or delete them.

**Who sees what:**

| Agent | Spec/tasks | Acceptance tests (location + content) | Acceptance result |
|---|---|---|---|
| Spec agent, dependency checker | writes/reads | — (do not exist yet) | — |
| **Test author** (step 3b) | reads | **writes** | — |
| Orchestrator | reads | **no** — only manifest + runner output | yes |
| Implementer, fix agent | reads | **no** | only filtered feedback (see below) |
| Reviewer | reads | **no** | only "green/red, N/M" |
| **Acceptance judge** (step 5, only on red) | reads | reads | writes the filtered feedback |

**Rules:**

1. **Location:** `Z = {{SEALED_ROOT}}/<slug>-<random>` (`random` = 8 hex characters), **outside**
   `R`, `W` and `S` — a repo or spec search does not find them. The path is only in
   the pointer `{{SEALED_ROOT}}/index/<slug>` (not in `$L` — every subagent gets that), never in the log, never in `tasks.md`/`design.md`, never in a
   prompt to an implementer, fix agent or reviewer.
2. **The orchestrator stays blind:** It never reads the test files (no `Read`, no `cat` on `Z`)
   until the run is over. Otherwise they leak through its context into every later prompt —
   and into every `fork`. Implementers, fix agents and reviewers are therefore **always fresh
   agents** (`general-purpose`), never `fork`.
3. **Implementer briefing** (in `context.md`): "There are sealed acceptance tests for this
   spec. You do not get them and must not look for them. Build against the requirements and
   interfaces in the spec, not against guessed tests. Read and write only in `W` and
   `S`." The implementer still writes its own tests (TDD) — those belong in the repo.
4. **Define interfaces:** So that the test author and the implementer can work independently
   of each other, `design.md` (or the short plan) contains a section
   **"Interfaces"**: public functions/signatures, routes with request/response,
   CLI calls, UI selectors/IDs, error codes. The implementer must build them **exactly like that**;
   a deviation is a spec violation, not a matter of style. Every requirement gets a
   **requirement ID** (`A1`, `A2`, … in `proposal.md`/specs).
5. **Run without placing:** `{{ACCEPTANCE_RUN}}` runs the tests from `Z` against `W`
   without copying them into `W` (read-only mount into a throwaway container, or a copy of
   `W` + `Z` into a temp directory that is deleted afterwards). The tests are thus never in
   a commit that an implementer sees.
   **The output is part of the seal:** A normal test run prints the tests' source code
   and values on red (tracebacks, assertions). `{{ACCEPTANCE_RUN}}` therefore prints **only**
   the summary + names of the red tests (e.g. pytest `--tb=no -rf`, the rest cut off via `sed`),
   and the output file lives in `{{SEALED_ROOT}}/out/<slug>-<n>.txt` — **never**
   under `$W` (implementers and fix agents read `$W/.superpowers/`). The long version with
   tracebacks is produced only by the acceptance judge (rule 7) itself, also into
   `{{SEALED_ROOT}}/out/`.
6. **Tamper protection:** Before every acceptance run, `sha256sum` over `Z` against the manifest in the
   log — mismatch = **abort** ("acceptance tests modified"). In addition the
   orchestrator checks in the diff whether the run changes test infrastructure such that other tests
   run differently (test configuration, global fixtures/`conftest`, skip/xfail markers, environment
   detection "is a test running right now?"): every such change must be justified by a task in `tasks.md`,
   otherwise it is a `blocker` for the security reviewer (it gets this list).
7. **Filtered feedback on red** (`{{ACCEPTANCE_FEEDBACK}}`): The fix agent never gets
   the test code. A fresh **acceptance judge** (reads tests + output, changes nothing)
   writes one line per red test:
   `A<n> | <requirement in its own words> | expected: <behavior> | observed: <behavior>`
   — with `requirement` without concrete test values that are not already in the spec; with
   `assertion` additionally test name, assertion text and traceback head (never the file).
   The judge also assesses whether the **test** is wrong (contradicts spec or
   interfaces) — then `TEST_ERROR A<n> | reason`, and the orchestrator has the
   test author fix exactly that test (new manifest into the log, counts as a
   repair attempt). A test is never deleted to get green.
8. **After the run:** If everything is green and the review loop has passed, the
   orchestrator commits the acceptance tests under `{{ACCEPTANCE_COMMIT_DIR}}`
   (`test(<slug>): acceptance tests`) — from then on they are normal regression tests. This happens
   in step 7 **after** the last review round and before the rebase; the full suite runs
   again afterwards anyway. Empty slot → do not commit, `Z` stays in place for later runs
   (path in the report). **After this commit no fix commit may
   touch `{{ACCEPTANCE_COMMIT_DIR}}`** (the tests are now normal files in the worktree) —
   the orchestrator checks the diff of every later fix commit, violation = abort.
9. **Honest limit:** The isolation is omission + instruction + filtered output +
   after-the-fact checks (hash, diff check), not a hard sandbox. An agent with a shell could search the
   file system. If you want it harder: `Z` on a path/host the session has no
   read access to, and `{{ACCEPTANCE_RUN}}` as a service that only returns "passed/failed".
   The report states which variant ran.

## Commands

`W` (and the other paths except `Z`) is passed **verbatim** to **every** subagent — a
`$(pwd)` in a subagent shell points to the session folder, not to the worktree.
The **full** suite and artifact builds always go through the queue
("Parallel operation") — also in step 4 and in subagents.

- Full suite: `{{TEST_FULL}}`
- Only if `{{DEPS_FILES}}` is in the diff: `{{TEST_FULL_FRESH_DEPS}}` (do not swallow installation errors)
- One file (immediately): `{{TEST_ONE}}`
- Light suites (immediately): `{{TEST_LIGHT}}`
- Acceptance (orchestrator only): `{{ACCEPTANCE_RUN}}`

Do not count `{{KNOWN_LOCAL_FAILURES}}` as failures; mention them in the report.

## Steps

1. **Intake and preflight.**
   - Slug from the idea (kebab-case, ≤ 4 words).
   - Determine paths (table above), read `factory.config.md` and `{{PROJECT_RULES}}` (not
     loaded automatically when starting outside the repo), `mkdir -p "$L"`, then
     take the **run lock** (see "Parallel operation"). If that fails: stop.
   - **Resume:** If `$S/factory-log.md` exists, resume the run from the last logged
     step (show the approval gate again if it was not answered yet; `Z` from
     the pointer `{{SEALED_ROOT}}/index/<slug>`; if the file is missing but the manifest is in the log: redo step 3b,
     new manifest). If a change or worktree exists **without** a log: stop, name it
     (the slug is taken by hand or by another tool — suggest a different slug).
   - **Start it yourself, don't stop:** If a runtime prerequisite is missing (Docker daemon,
     local instance), first run `{{AUTOSTART}}` and wait in the background until it
     responds (into the log). Only if that fails: stop and say what is missing.
   - Preflight, every item must hold, otherwise stop and say what is missing:
     `{{PREFLIGHT}}`; `git -C "$M" ls-remote origin {{TARGET_BRANCH}}` reachable; `openspec`
     and `docker` (if used) present; no old container of your own `factory-<slug>-*`
     (otherwise remove it — it belongs to this slug). Uncommitted changes in `M` and containers
     of other runs are **not** an obstacle — just mention in the report that the
     before screenshots show the state of `M`.
   - **External prerequisites:** If the idea names a system outside the repo (URL, service,
     account, token, server configuration), check every access with `curl -sI` — only the
     status code counts, not a guess. The result goes into the log header as `Prerequisite:`.
     If a prerequisite is not met (4xx/5xx, unreachable, access
     missing), do not stop. But it becomes the first decision point at the approval gate (step 3).
     (Lesson: a run built for 3 h against a 401.)
   - `git -C "$M" fetch origin && git -C "$M" worktree add "$W" -b {{FEATURE_BRANCH}} origin/{{TARGET_BRANCH}}`,
     create the log.

2. **Spec** — in subagents, so the main context stays small.
   - **Preliminary tiering** (orchestrator, a few greps): If the idea clearly meets `{{TIER_S}}`,
     there is no spec but a **short plan**. When in doubt, not S.
     The orchestrator writes `$S/tasks.md` itself, without OpenSpec and without `validate`:
     goal (1 sentence), requirements with IDs, interfaces (if there are any), tasks with
     real files (first look for source guards in the tests for that spot), test plan (2–3
     lines, views in `{{SCREEN_WIDTHS}}`), at most 3 decision points (see approval gate). Then
     go directly to step 3; the rest of step 2 is skipped.
   - **Spec agent** (`general-purpose`): runs the skill `openspec-propose` in folder `R`,
     change name = slug; gets `R`, `M`, `S` and the path `{{PROJECT_RULES}}`.
     Requirements in the prompt: **no questions to the user** — every open question becomes an assumption with a default;
     ignore the final recommendation "/opsx:apply". Required sections:
     - **Assumptions** in `proposal.md`;
     - **Requirements with IDs** (`A1 …`), each phrased testably (input → behavior);
     - **Interfaces** in `design.md` (see "Sealed acceptance tests", rule 4);
     - **Test plan** in `design.md`: unit tests; for stateful or dialog-like
       flows, scenario tests over several steps; for frontend, the views for the
       browser (`{{SCREEN_WIDTHS}}`); for `{{REVIEW_RUNTIME}}` paths, the harness scenarios
       (name existing ones from `$T`, describe what is missing as a new scenario with expectation —
       it is created in step 4 in `{{HARNESS_SCENARIO_FILE}}`, names with prefix
       `<slug>_`).
     The test plan names **test types and areas**, no concrete acceptance test cases — those
     are written sealed by the test author in step 3b. Tasks name real files (read the code
     with grep first). `openspec validate <slug>` green. The spec grows with the change: a
     pure presentation change gets few tasks and a short test plan, not a novel.
     Return only: goal (1 sentence), requirement IDs, tasks, test plan, `PREREQUISITES` (what
     must exist outside the code) and **`DECISION_POINTS`**: at most 3 assumptions where
     a different answer clearly changes the visible result, the architecture or the effort.
     Per decision point: question, 2–3 options (default first), for visuals an
     ASCII sketch per option (≤ 12 lines). The remaining assumptions are only in `proposal.md`.
   - **Dependency checker** (`reviewers.md` §3, mode "before the build") afterwards. Its
     `TASKS_ADD`/`ASSUMPTIONS_ADD` are entered by the orchestrator into `tasks.md`/`proposal.md`
     (marked "added: dependencies"), then `openspec validate <slug>` again. Its
     `TIER` and `REASON` go into the log header. It adds `DECISION_POINTS_ADD` and
     `PREREQUISITES_ADD` to those of the spec agent. If there are more than 3 decision points,
     it keeps the 3 with the greatest impact; the rest become assumptions with defaults.

3. **Approval gate.** A list of 20 assumptions gets nodded through in a minute, and the real
   design questions only come up after the push. That is why the approval gate asks about the decision points instead of
   listing assumptions.
   - Summary in the terminal, at most 10 lines:
     - **unmet prerequisites first and in bold**,
     - goal,
     - tier with reason and what it means (e.g. "S: one implementer, UI review only,
       {{TIER_MINUTES}}"), and whether sealed acceptance tests run,
     - task groups as headings with counts,
     - "N more assumptions with defaults in `proposal.md`". Do not list them.
   - Then **one** `AskUserQuestion` with up to 4 questions:
     - up to 3 decision points (default as first option, "(Recommended)"), for visuals with `preview`
       = ASCII sketch per option;
     - last **Build** / **Change** / **Abort**.
   - An **unmet prerequisite** is always the first decision point:
     - "Clarify first: stop the run (Recommended)", if the core of the idea depends on it.
       That counts as Abort.
     - "Build anyway, tested only against a mock". That then appears in the report under
       "open".
   - Answers into the log.
   - If a decision point deviates from the default and the last answer is "Build": work the answer in via
     `openspec-update-change` (S: directly in `tasks.md`) and build **without** another
     approval gate.
   - Change → work the note in via `openspec-update-change`, approval gate again. If the user
     only wants a different tier, change the tier in the log (no spec change) and ask
     again. If S becomes a higher tier in the process, redo step 2 from the spec agent on.
   - Abort → worktree, change and log stay, release the run lock, name the paths, end.

3b. **Write acceptance tests (sealed)** — only in tiers per `{{ACCEPTANCE_TIERS}}`,
   starts right after "Build" and runs **in parallel** with step 4.
   - Create `Z` (`mkdir -p`, random suffix), path into the pointer `{{SEALED_ROOT}}/index/<slug>`.
   - **Test author** (fresh `general-purpose`, never `fork`; model like the tier's reviewers)
     gets: `S` (spec after the approval gate), `M` (code state **before** the change, read-only),
     `Z`, `{{ACCEPTANCE_STYLE}}`, `{{ACCEPTANCE_RUN}}`, `{{PROJECT_RULES}}`. **Not** `W` —
     the author should write against the spec, not against the code being built.
   - Assignment:
     - at least one test per requirement ID, named after the ID (`test_A3_…`), so that
       a red test is understandable without source code;
     - **additionally edge cases that are not listed in `tasks.md`**: empty/boundary values,
       invalid inputs, permissions/roles (`{{SECURITY_ROLES}}`) for L, error paths,
       repetition/idempotency, long text and escaping for customer data;
     - only against the interfaces from `design.md` — no assumptions about internal
       helper functions, file names or implementation details;
     - write nothing in `W`, `S` or `M`; no commit;
     - tests for **new** interfaces in separate files, apart from tests for
       existing behavior (otherwise an import of a not-yet-existing interface turns the
       whole file into a collection error);
     - run once against the **base state** (`M`): the tests for new behavior
       must be **red** there (otherwise they test nothing), tests for existing behavior green.
   - Return **only**: number of tests per requirement ID, list of edge-case categories,
     result against base (red/green per ID), `sha256sum` per file. **No test code, no
     test values.** That goes into the log as the manifest.
   - The orchestrator does not read the files in `Z`.

4. **Build.**
   - First `git -C "$W" fetch origin && git -C "$W" rebase origin/{{TARGET_BRANCH}}`: spec and
     approval gate often take 20+ min, in that time other people's commits land (without own commits a
     pure fast-forward). New base into the log and into `tasks.md`/`design.md`, if a SHA
     appears there.
   - Skill `superpowers:subagent-driven-development` with these requirements:
     plan = `$S/tasks.md`; the worktree **already exists** (`W`, no new one, no
     `using-git-worktrees`); ticking off in `$S/` and Docker test runs are allowed and **not** a
     reason to stop; implementers commit per task (`{{COMMIT_STYLE}}`). **Dropped:** the
     SDD final review and `superpowers:finishing-a-development-branch` — steps 6 and 7
     take care of that.
   - **Tier S:** no SDD — one implementer gets all groups at once, commits per
     task, no task review (the UI review in step 6 is the check). Continue with step 5.
   - **Tier M/L:** one implementer and — per tier — one task review per task group
     (`## N.` in `tasks.md`), not per individual task. SDD's `task-brief` looks for
     "Task N" headings and finds nothing in OpenSpec tasks — cut the brief per group
     yourself:
     `awk -v n=N '/^## /{in_=($0 ~ "^## " n "[.]")} in_' "$S/tasks.md" > <workspace>/group-N-brief.md`.
     Write what all subagents need (paths except `Z`, commands above with `W` filled in,
     commit style, path to `{{PROJECT_RULES}}`, "full suite only via `queue.sh`", **the
     acceptance test note from rule 3**) **once** as `<workspace>/context.md` and
     pass only the path in each prompt. `<workspace>` = output of SDD's `sdd-workspace`
     (lives in `$W/.superpowers/`, gitignored).
   - Full suite after groups per tier (L: each, M: those that change backend code, S: none).
     Result into the log.
   - New harness scenarios from the test plan are created by the implementer in
     `{{HARNESS_SCENARIO_FILE}}` (lives outside the repo, is not committed); into the
     log.

5. **Verify** (fresh on every entry, 3 repair attempts).
   - Full suite (via the queue) and light suites. Red → fix the cause
     (`superpowers:systematic-debugging`), commit, test again. After 3 attempts:
     **abort** (see below).
   - **Acceptance tests** (if `Z` exists; waits until step 3b is done): check the manifest
     (rule 6), then `{{ACCEPTANCE_RUN}}` (heavy → via the queue). The orchestrator
     reads only the exit code and summary (passed/total, IDs of the red tests).
     - Green → into the log ("acceptance N/N, manifest ok").
     - Red → **acceptance judge** (fresh agent, rule 7; gets `Z`, runs the red tests
       itself with full traceback into `{{SEALED_ROOT}}/out/`) writes the filtered
       feedback to `$S/acceptance-feedback-<n>.md`; before passing it on, the orchestrator only
       checks that it contains no test code (no `def test`/`assert`/`expect(`
       lines). A **fresh** fix agent gets this file + spec + `W` (behavior first
       as its own test in the repo, then the fix, one commit `fix(<area>): acceptance A<n>`).
       Then step 5 again. Counter "acceptance repair" (log).
       `TEST_ERROR` → the test author fixes exactly that test (rule 7).
   - **Runtime paths in the diff** (`{{REVIEW_RUNTIME}}`) **and** changed since the last build
     (SHA in the log): build once (via the queue),
     `{{ARTIFACT_BUILD}}`. The first time, additionally the **baseline**:
     `git -C "$M" worktree add "$W-base" <base-SHA>`, `{{TEST_FULL_LIST}}` there, pass/fail list
     to `$S/baseline-tests.txt`.
   - **Scenario harness** (only if `{{HARNESS_DIR}}` is set and runtime paths are in the diff,
     after the build). `B` = first 7 characters of the base SHA.
     1. Build the base artifact `base-$B` only if it does not exist yet (other runs on
        the same base share it), via the queue: `{{ARTIFACT_BUILD_BASE}}`.
     2. Scenarios = `{{HARNESS_STD_SCENARIOS}}` plus those from the test plan. Per artifact
        at least 2 runs, via the queue (`{{HARNESS_RUN}}`). For `base-$B` only
        scenarios that do not yet have 2 results with this artifact.
     3. Comparison `{{HARNESS_COMPARE}}`, table and summary into the log.
        - **Re-measure:** Two runs do not separate noise from regression. A flagged
          scenario is therefore brought up to 6 runs with the run's artifact, only then is it
          compared.
        - **A regression after re-measuring counts like a red test.**
        - Also red: a test plan scenario that is not 2/2 ok with the run's artifact.
        - Repair as above, then rebuild and rerun only the run's artifact.
     4. `{{HARNESS_NOTES}}` — if a result is missing, read the harness logs first before
        doubting the code.
   - **`{{PREVIEW_TRIGGER}}` in the diff:** preview instance (start once, hot reload picks up
     changes itself): `{{PREVIEW_START}}`. `P` = first free port from
     `{{PREVIEW_PORTS}}` (`curl -s 127.0.0.1:$P` does not respond). If the start fails on the
     port (another run was faster), remove the container and take the next port.
     `P` into the log. Always address it via `http://127.0.0.1:$P` (own cookie store,
     the shared instance stays logged in). `curl -sI http://127.0.0.1:$P/` must respond.
   - **Preview test data:** `{{PREVIEW_SEED}}` — synthetic data only: normal case,
     empty state, long text with `<img onerror>`. IDs of the test data into the log — the
     reviewers need them. Before screenshots of the shared instance show real data,
     after screenshots synthetic data; say so in the report.

6. **Review loop** — until **all** responsible reviewers report `APPROVED`.
   Checklists, responsibilities, response format and finding IDs: `reviewers.md`.
   1. **Completeness** (orchestrator, every round): no open `- [ ]` in `tasks.md`, and
      every task has a commit that implements it. Gap → back to step 4 only for those
      tasks.
   2. Determine responsibilities from `git -C "$W" diff --name-only origin/{{TARGET_BRANCH}}...HEAD`
      (anew every round), checking the tier against the real diff and escalating if
      necessary ("Tiers"). For S only the UI/UX reviewer.
   3. Start the responsible reviewers **in parallel** (one Agent call per reviewer in *one*
      message, `general-purpose`, fresh). Each gets `W`, `L`, `P`, slug, spec path, the
      commands above (without `{{ACCEPTANCE_RUN}}`), its open findings from the previous round (with IDs),
      its checklist, the diff as a file
      (`git -C "$W" diff origin/{{TARGET_BRANCH}}...HEAD > "$S/review-r<N>.diff"`), the
      acceptance result as a number ("acceptance 14/14 green") and — from round 2 on — the commit range
      of the last fix round. The security reviewer additionally gets the list of changed
      test infrastructure (rule 6). The full suite runs at the orchestrator in parallel with the
      round; reviewers do not run it again but get the result.
   4. Result into the log. All `APPROVED` → step 7.
   5. Otherwise **one** fresh fix agent with all `blocker`/`major` findings: behavior first
      as a test, then the fix, **one commit per round** (`fix(<area>): findings from review round N`).
      If findings contradict each other, `{{CONFLICT_ORDER}}` applies. Then step 5 (incl.
      acceptance tests), then the next round.
   6. **Abort** if: the tier's round limit is reached, or a finding ID is open again in the next round after
      a fix attempt and the second
      fix attempt does not close it either, or a fix would have to overturn a user decision from
      `{{PROJECT_RULES}}`. `minor` findings never block; they go into the
      report.

7. **Ship** — everything from "rebase" to "push" under the **push lock**.
   - Adopt the acceptance tests (rule 8): copy to `{{ACCEPTANCE_COMMIT_DIR}}`,
     commit `test(<slug>): acceptance tests` (skipped if the slot is empty).
   - `git -C "$W" status --porcelain` empty (otherwise commit).
   - Take the push lock (wait in the background, see "Parallel operation"), into the log.
   - `git -C "$W" fetch origin && git -C "$W" rebase origin/{{TARGET_BRANCH}}`. Conflict →
     `git -C "$W" rebase --abort`, **abort**.
   - If the rebase brought in other people's commits that touch the same files: one more
     review round (counts toward the tier's round limit).
   - Tests green one last time (step 5 without restarting the preview; the acceptance tests are
     now part of the suite; the harness only if the rebase changed runtime paths; the
     full suite also goes through the queue here, the push lock stays
     held). If the rebase brought in **nothing** and `HEAD` is exactly the SHA on which the last
     suite was green according to the log, the run is skipped — into the log ("tests green on identical
     SHA"). The acceptance test commit changes the SHA; then the suite runs once.
   - `git -C "$W" push origin HEAD:{{TARGET_BRANCH}}`. Rejected (someone outside the factory
     was faster): up to **twice** fetch, rebase, tests, push. Then → **abort**.
   - Release the push lock (`rmdir "$L/push"`), immediately after the push.
   - `git -C "$M" pull --ff-only` — **only** if `git -C "$M" status --porcelain --untracked-files=no`
     is empty (untracked local files do not block; the fast-forward does not touch
     them) and the branch is `{{TARGET_BRANCH}}`; otherwise skip and say in the report that
     the shared instance still shows the old state. Pipeline link for the log:
     `{{PIPELINE_URL}}`. `{{RELEASE_NOTE}}`
   - **Runtime paths in the diff:** The artifact used locally for live tests is **not** the
     run build `factory-<slug>` (lesson: a run was reported as done, and the live test
     then ran on a state from the morning).
     - If the pull in `M` succeeded, rebuild there, via the queue:
       `{{ARTIFACT_LOCAL_REFRESH}}`.
     - If the pull was skipped, do **not** build (the artifact would not contain the change).
       In the report, in bold: "local artifact NOT updated".
     - Running instances keep their old artifact — belongs in the report.

8. **Report and cleanup.**
   - Cleanup: `{{CLEANUP}}`, `git -C "$M" worktree remove "$W-base"`, seed data — each
     only if present. Delete `Z` if the tests are committed; otherwise leave it.
     Finally release the run lock (`rm -r "$L/run-<slug>"`).
   - **Name the status honestly.** Green tests and reviews do not prove that it works in real
     operation.
     - If the diff touches `{{LIVE_STATUS_PATHS}}`, the status is **"pushed – live test
       pending"**. Never "done".
     - The same applies to "build anyway" despite an unmet prerequisite (then: "pushed –
       tested against a mock").
     - This status is in the log, in the artifact and in the first sentence of the answer to the
       user, together with the live checklist.
   - Artifact "Factory: <slug>" from the log: status (pushed / pushed – live test
     pending / aborted + why), idea, assumptions, tasks ✓/✗, test counts, **acceptance**
     (tests per requirement ID, result against base and final state, repair rounds,
     isolation variant per rule 9), artifact built?, **review log** (rounds,
     verdicts, fixed findings, open `minor`), before/after screenshots **embedded
     directly** as `data:image/png;base64,…` (with more than 40 images only the changed
     views), before/after side by side, commit SHAs, pipeline link,
     **harness comparison**, **open live tests** as a checklist from the runtime reviewer.
     The harness does not replace the live test.
   - Then `{{POST_RUN_HOOK}}` (if set). Do **not** archive the OpenSpec change — that
     happens after the live test via `/opsx:archive` (S runs have no change, only
     `tasks.md` and the log). The feature worktree stays.

## Follow-up after the report

If the user looks at the result and then wants something different ("list only with date and
title"), their wish is the approval — no new approval gate. Precondition: it stays within the scope
of the change. Otherwise a new `/factory` run.
- In the same worktree `W`, `fetch` + `rebase` first. Take the run lock again.
- In `tasks.md` create a section "Follow-up (user request <date>)" with the tasks,
  line into the log.
- First find everything that depends on the changed spot (callers, source guards in the
  tests), then change it; adapt guards to the new behavior, do not delete them. This also applies
  to the committed acceptance tests: if the follow-up changes a requirement, the
  corresponding acceptance test is adapted and that is mentioned in the commit.
- Focused tests, browser check in the preview (reload seed data), full suite via
  `queue.sh`, one commit, push under the push lock, update `M`, clean up.
- Security reviewer only if backend routes or permissions are in the follow-up diff; otherwise the
  review loop is skipped. Do not rebuild the report artifact; mention the follow-up in the answer.

## Abort (from steps 3b–7)

The work is never lost: release the push lock if held, delete your own
queue ticket; abort a running rebase (`git -C "$W" rebase --abort`),
commit uncommitted changes as `wip(factory): <reason>`, if `{{ABORT_PUSH_OK}}`: back up **only the
feature branch** (`git -C "$W" push origin {{FEATURE_BRANCH}}`), reason and step into the
log, then step 8 with status "aborted". `Z` and the pointer
`{{SEALED_ROOT}}/index/<slug>` stay in place so that a later run reuses the same tests.
A later `/factory` with the same idea or the same
slug resumes there.

## Pitfalls (from real runs)

- `rm -f "$Q/$T"` triggers the rm safety check → write `"${Q:?}/${T:?}"`. Likewise
  `rm -rf out/...` for old harness runs: better build under a new tag (`factory-<slug>-r1`),
  then runs do not get mixed up.
- Python tools on Windows: emoji in the output crash with cp1252 → start with
  `PYTHONIOENCODING=utf-8` (otherwise the whole `&&` chain breaks).
- Git Bash: every path passed to `docker` needs `MSYS_NO_PATHCONV=1`, otherwise `/srv/…` becomes
  `C:/Program Files/Git/srv/…`.
- Git Bash: `$HOME` is `/c/Users/…`; with `MSYS_NO_PATHCONV=1` Docker Desktop does not understand
  that. Set `SEALED_ROOT` (and every other mount path) in Windows format, e.g.
  `$(cygpath -m "$HOME")/.factory-sealed`.
- `$(pwd)` in a subagent shell is the session folder, not the worktree — always pass paths
  verbatim.
- The `security-review` skill needs a git working directory; reviewers work with
  `git -C "$W"` or the diff file.
- A reviewer that calls `/logout` on the shared instance logs everyone out there —
  hence "view only".
- Is the factory worth it? For M/L with permissions/auth/data, yes (real findings: account takeover,
  role gaps, mobile line wrapping). For small UI changes S is the right mode; for
  one-line bug fixes a normal fix is faster.
