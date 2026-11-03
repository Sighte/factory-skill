# factory.config.md — project adapter for `/factory`

You copy this file as `factory.config.md` into the session folder `R` (recommended:
`$R/factory.config.md`, **outside** the repo — otherwise implementers read in the worktree, where the
sealed acceptance tests are located; fallback `<repo>/.claude/factory.config.md`) and fill in every slot. `SKILL.md` and `reviewers.md`
name only the slot names (`{{TARGET_BRANCH}}` etc.); the values live exclusively here.
An empty optional slot means: this part of the procedure is skipped.

A filled-in example is in `examples/meetingagent.factory.config.md`.

---

## 1. Paths and repo

| Slot | Meaning | Value |
|---|---|---|
| `SESSION_ROOT` | Folder in which the Claude session starts (`R`). Must contain the checkout `M` and the OpenSpec folder. | `…` |
| `REPO_DIR` | Name of the checkout under `R` (`M = $R/$REPO_DIR`), is on `TARGET_BRANCH`. | `…` |
| `WORKTREE_PATTERN` | Worktree per run (`W`). | `$R/$REPO_DIR-<slug>` |
| `OPENSPEC_DIR` | Where `openspec/changes/<slug>` lives (`S`). | `$R/openspec` |
| `LOCK_DIR` | Locks and queue (`L`). | `$R/.factory-locks` |
| `SEALED_ROOT` | Root of the sealed acceptance tests (`Z`), **outside** of `R`. | `$HOME/.factory-sealed` |
| `PATH_STYLE` | `posix` or `windows` (Git Bash: paths with `pwd -W`, every Docker path with `MSYS_NO_PATHCONV=1`). | `…` |
| `PROJECT_RULES` | File with invariants/user decisions that is the yardstick for all reviewers. | `$M/CLAUDE.md` |

## 2. Branches and hard limits

| Slot | Meaning | Value |
|---|---|---|
| `TARGET_BRANCH` | The factory pushes directly there (without an MR), after approval gate + green tests + acceptance tests + review. | `develop` |
| `PROD_BRANCH` | Is **never** touched (no push, no MR). | `main` |
| `PROTECTED_JOBS` | CI jobs/actions that the factory never triggers. | `…` |
| `FEATURE_BRANCH` | Branch pattern per run. | `feat/<slug>` |
| `ABORT_PUSH_OK` | May an aborted run save the feature branch (`git push origin feat/<slug>`)? Only yes if no expensive/deploying CI jobs run on feature branches. | `yes` |
| `PIPELINE_URL` | Link for log/report. | `…` |
| `RELEASE_NOTE` | One sentence on what is still missing after `TARGET_BRANCH` until it is live (e.g. "live only after release MR to main"). | `…` |

The exception "factory pushes directly to `TARGET_BRANCH`" must be stated in `PROJECT_RULES`,
otherwise reviewers report it as a finding.

## 3. Commands

Every command with `$W` as a placeholder for the worktree (inserted verbatim for the subagents).

| Slot | Meaning | Value |
|---|---|---|
| `TEST_FULL` | Full suite (heavy, runs via `queue.sh`). | ```…``` |
| `TEST_FULL_FRESH_DEPS` | Full suite with fresh dependency installation — only if `DEPS_FILES` is in the diff. | ```…``` |
| `TEST_ONE` | One test file (light, runs immediately). `<file>` as placeholder. | ```…``` |
| `TEST_LIGHT` | Further light suites (e.g. JS), run immediately. | ```…``` |
| `TEST_FULL_LIST` | Like `TEST_FULL`, but with a pass/fail list per test (for the baseline), e.g. `pytest -rA`. | ```…``` |
| `KNOWN_LOCAL_FAILURES` | Tests that fail locally for a known reason and do not count as red (name them in the report). | `…` |
| `DEPS_FILES` | Files whose change requires a fresh installation. | `requirements.txt` |
| `HEAVY_JOBS` | What **always** runs via `queue.sh` (one after another across all runs). | full suite, baseline, image builds, harness runs |

## 4. Sealed acceptance tests

| Slot | Meaning | Value |
|---|---|---|
| `ACCEPTANCE_STYLE` | How the acceptance tests are written: `unit` (same language/framework as the suite, against the public interfaces from the spec), `blackbox` (HTTP/CLI/browser against the running preview) or both. | `…` |
| `ACCEPTANCE_RUN` | Command that runs the tests from `$Z` against `$W` **without** placing them in `$W` (read-only mount or copy into a throwaway container). Output **only** summary + names of red tests, no tracebacks/assertions (e.g. `pytest -q --tb=no -rf … 2>&1 \| sed 's/ - .*$//'`). | ```…``` |
| `ACCEPTANCE_TIERS` | In which tiers there are sealed acceptance tests. Default `M,L` (optional for S). | `M,L` |
| `ACCEPTANCE_FEEDBACK` | What a fix agent sees on red acceptance tests: `requirement` (only requirement ID + behavior expected/observed, default) or `assertion` (test name + assertion text + traceback head, never the test file). | `requirement` |
| `ACCEPTANCE_COMMIT_DIR` | Where in the repo the tests are committed after acceptance passes (regression protection). Empty = do not commit. | `tests/acceptance/` |

## 5. Tier criteria (S/M/L)

Path globs and topics; the highest matching tier applies, when in doubt the higher one.

| Slot | Meaning | Value |
|---|---|---|
| `TIER_L` | Critical runtime path, permissions/roles, tenant isolation, parsing of external input, data protection, migration, public API. | `…` |
| `TIER_M` | Backend change, new/changed route, new field in the data model, frontend logic with its own state/data flow. | `…` |
| `TIER_S` | Only presentation/texts/layout in the frontend folder (+ tests for it), without new data or queries. | `…` |
| `TIER_MINUTES` | Rough duration per tier for the approval gate display. | `S ~10 min, M ~30 min, L 1–2 h` |

## 6. Reviewer responsibilities

| Slot | Reviewer | responsible if a changed file matches | Value |
|---|---|---|---|
| `REVIEW_SECURITY` | Security (§2) | Default: always (except S — there UI/UX also checks the frontend points) | `always` |
| `REVIEW_RUNTIME` | Runtime/critical path (§1) | Paths that go into a shipped artifact (image, binary, worker, mobile build …) | `…` |
| `REVIEW_UI` | UI/UX full (§4) | Frontend folder | `…` |
| `REVIEW_UI_TEXT` | UI/UX texts only (§4.5) | Customer-facing texts in the backend (error messages, mail texts) | `…` |
| `REVIEW_DEPS` | Dependencies, re-check (§3) | Diff touches files that do not appear in `tasks.md` | `always per rule` |

Additional, project-specific check items per reviewer:

```
SECURITY_EXTRA:
- …   (e.g. "bot access only via accounts.require_bot, foreign record → 404, never 403")
RUNTIME_EXTRA:
- …   (e.g. "new field reaches the container: both runners + fetch_config")
DEPS_EXTRA:
- …   (e.g. "CI path filter in .gitlab-ci.yml")
UI_EXTRA:
- …   (e.g. "customer texts: informal 'du' form, no internals")
SECURITY_ROLES: <role matrix per route, e.g. anonymous, member, foreign org, admin, superadmin, API token>
CONFLICT_ORDER: project rules > security > runtime quality > dependencies > visuals
```

## 7. Runtime artifact (optional, only if `REVIEW_RUNTIME` is set)

| Slot | Meaning | Value |
|---|---|---|
| `ARTIFACT_BUILD` | Build the artifact from `$W` (heavy, via `queue.sh`), tag with slug. | ```…``` |
| `ARTIFACT_BUILD_BASE` | The same from the base worktree, tag `base-<B>` (shared between runs on the same base). | ```…``` |
| `ARTIFACT_IMPORT_CHECK` | Smoke test in the built artifact (e.g. import of all changed modules). | ```…``` |
| `ARTIFACT_LOCAL_REFRESH` | What updates the locally used artifact after the push (otherwise the user tests the old state live). | ```…``` |
| `RUNTIME_CORE_FUNCTIONS` | Core functions that, point by point, must be covered by a green test or be justifiably untouched. | List |
| `LIVE_CHECKLIST_ALWAYS` | Items that are always on the live checklist (what no local check covers). | List |
| `LIVE_STATUS_PATHS` | Diff touches these → status "pushed – live test pending", never "done". | `…` |

## 8. Scenario harness (optional)

A mock/simulator against which the real artifact runs (end-to-end). Empty = skipped.

| Slot | Meaning | Value |
|---|---|---|
| `HARNESS_DIR` | Folder (`T`), outside the repo. | `…` |
| `HARNESS_STD_SCENARIOS` | Standard set, runs on every run with runtime paths. | `…` |
| `HARNESS_RUN` | `<image> <scenarios> -n <N>` | ```…``` |
| `HARNESS_COMPARE` | Comparison base vs. run with re-measurement; exit 1 = regression. | ```…``` |
| `HARNESS_SCENARIO_FILE` | Where new run scenarios go (not committed). | `$T/scenarios_<slug>.py` |
| `HARNESS_NOTES` | Known pitfalls (encoding, read logs first …). | `…` |

## 9. Preview instance (optional, for UI changes)

| Slot | Meaning | Value |
|---|---|---|
| `PREVIEW_TRIGGER` | Paths that require a preview. | `…` |
| `PREVIEW_PORTS` | Port range, the first free one is taken. | `8081-8099` |
| `PREVIEW_START` | Start command (`<slug>`, `$P`, `$W` as placeholders), own copy of the data, hot reload. | ```…``` |
| `PREVIEW_SEED` | How synthetic test data is loaded (normal case, empty state, long text with `<img onerror>`). | `…` |
| `SHARED_INSTANCE` | Shared instance of other sessions (before screenshots), **read only**. | `http://127.0.0.1:8080` |
| `SHARED_INSTANCE_DONTS` | What is forbidden there (logout, writing requests …) and why. | `…` |
| `SCREENSHOT_TOOL` | Headless screenshot tool that can run in parallel (not the shared Playwright MCP). | `…` |
| `SCREEN_WIDTHS` | Widths. | `1280 390` |
| `STYLE_SOURCE` | Style guide/components that new work must measure up to. | `…` |
| `CLEANUP` | What step 8 removes (containers, volumes, images, base worktree, seed data). | List |

## 10. Preflight and misc

| Slot | Meaning | Value |
|---|---|---|
| `PREFLIGHT` | List of checks that must all pass (remote reachable, tools present, instance responds …). | List |
| `AUTOSTART` | Commands that start missing runtime requirements themselves (Docker Desktop, `docker compose up -d` …), each with a wait time. | empty |
| `SECRETS_RULES` | What is never read/output (`.env` …), exceptions. | `…` |
| `COMMIT_STYLE` | Commit style + language. | `feat(<area>): …` + `Co-Authored-By` |
| `POST_RUN_HOOK` | Optional skill/command after the report (e.g. status to a task tracker). | empty |
| `MODELS` | Model choice per tier (implementer/reviewer). | `S: sonnet · M: Reviewer ≥ sonnet · L: opus for logic` |
