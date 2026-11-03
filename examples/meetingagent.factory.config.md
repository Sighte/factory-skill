# factory.config.md — Example: MeetingAgent (original project)

Filled-in adapter of the project in which the factory was created: FastAPI WebUI
(control host) + bot container (Teams meeting agent), Windows/Git Bash, Docker, GitLab.
Shows how concretely the slots are meant.

## 1. Paths and repo

| Slot | Value |
|---|---|
| `SESSION_ROOT` | `meetingagent-neu/` (contains `MeetingAgent/` and `openspec/`) |
| `REPO_DIR` | `MeetingAgent` — checkout on `develop`, mount of the local instance :8080 |
| `WORKTREE_PATTERN` | `$R/MeetingAgent-<slug>` |
| `OPENSPEC_DIR` | `$R/openspec` |
| `LOCK_DIR` | `$R/.factory-locks` |
| `SEALED_ROOT` | `$(cygpath -m "$HOME")/.factory-sealed` (Windows format, otherwise Docker Desktop does not find the mount) |
| `PATH_STYLE` | `windows` |
| `PROJECT_RULES` | `$M/CLAUDE.md` |

## 2. Branches and hard limits

| Slot | Value |
|---|---|
| `TARGET_BRANCH` | `develop` |
| `PROD_BRANCH` | `master` |
| `PROTECTED_JOBS` | `bot_image_latest` (sets `:latest` for the entire customer fleet), `deploy_config`, `bot_smoke` |
| `FEATURE_BRANCH` | `feat/<slug>` |
| `ABORT_PUSH_OK` | yes — on feature branches only `pytest` runs, no Fly jobs |
| `PIPELINE_URL` | `https://gitlab.usecaise.net/usecaise-platform/meetingagent/-/pipelines?ref=develop` |
| `RELEASE_NOTE` | `develop` does not build a bot image and does not deploy the WebUI — live only with the release to `master` (`bot_image` → `bot_smoke` → `bot_image_latest`). |

## 3. Commands

```bash
# TEST_FULL (image of the local instance has requirements + pytest)
MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/src:ro" -e WEBUI_SECRET=ci-secret meetingagent-local-webui:latest \
  sh -c "cp -r /src /app && cd /app && python -m pytest -q -p no:cacheprovider"
# TEST_FULL_FRESH_DEPS (only if requirements.txt is in the diff)
MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/src:ro" -e WEBUI_SECRET=ci-secret python:3.12-slim \
  sh -c "cp -r /src /app && cd /app && pip install -q -r requirements.txt && python -m pytest -q -p no:cacheprovider"
# TEST_ONE
… python -m pytest -q -p no:cacheprovider tests/<file>.py
# TEST_LIGHT (JS)
MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/w" -w /w node:22 sh -c "node --test webui/static/*.test.js"
# TEST_FULL_LIST
like TEST_FULL with `-rA`
```

| Slot | Value |
|---|---|
| `KNOWN_LOCAL_FAILURES` | `test_preview_uses_the_bot_file` (CRLF only under Windows) |
| `DEPS_FILES` | `requirements.txt` |
| `HEAVY_JOBS` | full Python suite (also baseline and the reviewers' suites), bot image build, simulator runs (fixed containers `teams-sim`/`bot-sim`, only one at a time) |

## 4. Sealed acceptance tests

| Slot | Value |
|---|---|
| `ACCEPTANCE_STYLE` | `unit` (pytest against the interfaces from `design.md`, server via FastAPI TestClient) + for UI `blackbox` (headless Chrome against the preview `:$P`) |
| `ACCEPTANCE_RUN` | ```MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/src:ro" -v "$Z:/acc:ro" -e WEBUI_SECRET=ci-secret meetingagent-local-webui:latest sh -c "cp -r /src /app && cp -r /acc /app/tests/_acceptance && cd /app && python -m pytest -q -p no:cacheprovider --tb=no -rf tests/_acceptance" 2>&1 \| sed 's/ - .*$//'``` |
| `ACCEPTANCE_TIERS` | `M,L` |
| `ACCEPTANCE_FEEDBACK` | `requirement` |
| `ACCEPTANCE_COMMIT_DIR` | `tests/acceptance/<slug>/` |

## 5. Tier criteria (S/M/L)

| Slot | Value |
|---|---|
| `TIER_L` | `core/`, `docker/` or another bot image path; speech, gate, TTS, prompt; permissions/roles (`accounts`, `require_bot`, levels, approvals, org token); tenant isolation; parsing of external input (mails, .ics, uploads); new storage location for meeting data or data protection path (`purge_window`, opt-out, `effective_meeting_sources`); migration of existing data; integration API `/api/v1` |
| `TIER_M` | a `webui/*.py` changes; new or changed route; new field in a store; frontend logic with its own state, routing or data flow (deep link, autosave, new API query) |
| `TIER_S` | only presentation, texts, layout or rework of existing views in `webui/static/` (and tests for it), without new data or queries |
| `TIER_MINUTES` | S ~10 min, M ~30 min, L 1–2 h |

## 6. Reviewer responsibilities

| Slot | Value |
|---|---|
| `REVIEW_SECURITY` | always (except S) |
| `REVIEW_RUNTIME` | `core/`, `docker/`, `Dockerfile`, `bin/start_chromium_cdp.sh`, `prompts/system.md`, `requirements.txt`, `fly.toml`, `pyproject.toml`, or a `webui/*.py` that `.dockerignore` does **not** exclude — the current `.dockerignore` is authoritative |
| `REVIEW_UI` | `webui/static/` or `core/avatar.js` |
| `REVIEW_UI_TEXT` | customer-facing text in `webui/*.py` (`detail=`, `HTTPException`, `FieldError`, `LAUNCH_ERRORS`, mail texts) |

```
SECURITY_ROLES: anonymous, member, member of a foreign org, org_admin, operator superadmin, org token, bot token
SECURITY_EXTRA:
- Bot access only via accounts.require_bot(bot_id, user, level) with the correct level
  (read/content/write/admin/own); foreign agent → 404, never 403.
- Superadmin has only read + admin, no write/content. Org token rules from CLAUDE.md.
- tests/test_route_guard.py green and MIN_ROUTES still matching.
- Account mails with record=False.
- New storage location for meeting data → purge_window and purge_bot_data; audit line.
RUNTIME_EXTRA:
- New field reaches the container: both runners (_run_args, _bot_launch_config) and fetch_config.
- Import check: docker run --rm --entrypoint /opt/venv/bin/python -w /srv/teams-meeting-bot/core
  meetingagent-local-bot:factory-<slug> -c "import <module>"
DEPS_EXTRA:
- New agent field: bots_store.check_fields, both runners, core/fetch_config.py, /api/v1 (schema,
  old clients), templates, assistant, default for existing data.
- Ops button: container_runner._PASS_ENV ↔ server._OPS_ENV; per-bot fields NOT there.
- core/ imports something new → .dockerignore and test_audit_fixes.py.
- Old bot images in prod (:latest is pulled manually): host with old bot and vice versa.
- CI path filter in .gitlab-ci.yml (new webui/static/*.test.js → job frontend_test;
  new bot image paths → .bot_image_changes); requirements.txt/requirements.lock in sync.
- DE/EN texts; TestCustomerWording.
UI_EXTRA:
- Customer texts: informal "du", no internals (list in CLAUDE.md "Kundentexte"), only Teams as platform.
CONFLICT_ORDER: CLAUDE.md invariants > security > bot quality > dependencies > visuals
```

## 7. Runtime artifact (bot image)

| Slot | Value |
|---|---|
| `ARTIFACT_BUILD` | `docker build -t meetingagent-local-bot:factory-<slug> "$W"` (shares the cache with `docker compose build bot`) |
| `ARTIFACT_BUILD_BASE` | `docker build -t meetingagent-local-bot:base-$B "$W-base"` (only if `docker image inspect` does not find it) |
| `ARTIFACT_IMPORT_CHECK` | see `RUNTIME_EXTRA` |
| `ARTIFACT_LOCAL_REFRESH` | `docker compose -f "$R/meetingagent-local/compose.yml" build bot` (image `meetingagent-local-bot:latest`, which "Ins Meeting schicken" starts on :8080); running bots: "Meeting verlassen" and send again |
| `RUNTIME_CORE_FUNCTIONS` | Joining, lobby, automatic leaving, teardown via `finish_meeting` (also SIGTERM) · AI notice in the chat, display name "- KI", opt-out via "OUT" and by calling out · speech gate: answer to name, no interrupting without reason, `REPLY_MAX`, followup · announcement by the tool, tool result is spoken · scenarios over multiple turns (two questions in a row, question while the bot is speaking, being addressed after someone else's conversation, sentence with date and number) · summary and mail, glossary, `MEETING_SOURCES`, speaker attribution · synchronous I/O in tools in `asyncio.to_thread` |
| `LIVE_CHECKLIST_ALWAYS` | real Teams DOM (selectors), echo via the participants' speakers, real network latency; after the release `master` → `bot_smoke` in the Teams meeting |
| `LIVE_STATUS_PATHS` | bot image paths, speech, gate, prompt, tools |

## 8. Scenario harness (Teams simulator)

| Slot | Value |
|---|---|
| `HARNESS_DIR` | `$R/meetingagent-local/teamssim` — real bot container against a Teams mock (joining, lobby, roster, chat/opt-out, speech, leaving, summary mail in Mailpit) |
| `HARNESS_STD_SCENARIOS` | `s3_direkt s5_nachfrage s6_diskussion s7_unterbrechen t3_optout t5_ende` |
| `HARNESS_RUN` | `bash "$K/queue.sh" "$L" <slug>-sim <output> env PYTHONIOENCODING=utf-8 python "$T/sim.py" run factory-<slug> <scenarios> -n 2` |
| `HARNESS_COMPARE` | `env PYTHONIOENCODING=utf-8 python "$T/sim.py" compare base-$B factory-<slug> <scenarios> --nachmessen` → `$T/out/compare-base-$B-vs-factory-<slug>.md`; exit 1 = regression |
| `HARNESS_SCENARIO_FILE` | `$T/scenarios_<slug>.py` (`SCENARIOS = {...}`, optionally `VOICES`; `sim.py` loads the file itself) |
| `HARNESS_NOTES` | One run ≈ 1.5 min. If `result.json` is missing, the bot usually never joined → first `$T/out/<run>/bot.log`. `sim.py` reads provider keys itself from the `.env` (never output them). The most recently run sim image is attached to the shared `bot-sim` container and cannot be removed without force. |

## 9. Preview instance

| Slot | Value |
|---|---|
| `PREVIEW_TRIGGER` | `webui/static/` or `core/avatar.js` |
| `PREVIEW_PORTS` | `8081-8099` |
| `SHARED_INSTANCE` | `http://127.0.0.1:8080` |
| `SHARED_INSTANCE_DONTS` | no logout (`/api/logout` invalidates all sessions of the demo account via `bump_epoch`), no POST/PUT/PATCH/DELETE, do not create or save anything; do not send agents into a meeting |
| `SCREENSHOT_TOOL` | `meetingagent-neu/.playwright-mcp/shot.mjs` (env `BASE`, `CDP_PORT`; puts images next to itself, outputs console errors) |
| `SCREEN_WIDTHS` | `1280 390` |
| `STYLE_SOURCE` | UseCaise style guide (styleguide.usecaise.net: tokens, fonts, uc components) + existing WebUI components |

```bash
# PREVIEW_START
MSYS_NO_PATHCONV=1 docker run --rm -v meetingagent-local_state:/from:ro -v factory-<slug>-state:/to python:3.12-slim cp -a /from/. /to/
MSYS_NO_PATHCONV=1 docker run -d --name factory-<slug>-webui -p 127.0.0.1:$P:8080 \
  --network meetingagent-local_default -v "$W:/srv/teams-meeting-bot" \
  -v factory-<slug>-state:/srv/teams-meeting-bot/state -v /var/run/docker.sock:/var/run/docker.sock \
  -w /srv/teams-meeting-bot/webui -e WEBUI_SECRET=factory-preview \
  -e LIVEKIT_API_KEY=dummy -e LIVEKIT_API_SECRET=dummy \
  -e MAILCOW_BASE_URL=http://fake-mailcow:8000 -e MAILCOW_API_KEY=fake -e MAILCOW_DOMAIN=demo.local \
  -e WATCHFILES_FORCE_POLLING=true meetingagent-local-webui:latest \
  uvicorn server:app --host 0.0.0.0 --port 8080 --reload --reload-dir /srv/teams-meeting-bot/webui
# Docker socket is needed by /api/fleet (otherwise "Verbindung gestört"). requirements.txt in the diff →
# before uvicorn `pip install -r ../requirements.txt` (sh -c).
```

`PREVIEW_SEED`: accounts/agents/invitations come from the copy of `state/`, meetings and
transcripts do **not** (`transcripts/` is empty in the worktree, gitignored). Seed script
`$W/transcripts/seed_<slug>.py` via `meeting_knowledge_store.add_meeting` /
`invites_store.upsert_invite`, load via
`MSYS_NO_PATHCONV=1 docker exec factory-<slug>-webui python /srv/teams-meeting-bot/transcripts/seed_<slug>.py`.

`CLEANUP`: `docker rm -f factory-<slug>-webui`, `docker volume rm factory-<slug>-state`,
`docker rmi meetingagent-local-bot:factory-<slug>`, seed data in `$W/transcripts/`.

## 10. Preflight and misc

| Slot | Value |
|---|---|
| `PREFLIGHT` | `curl -sI http://127.0.0.1:8080/` responds; `openspec`, `node`, `docker` present |
| `AUTOSTART` | Start Docker Desktop (`Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"`), wait up to 5 min for `docker info`; if :8080 then does not respond: `docker compose -f "$R/meetingagent-local/compose.yml" up -d webui`, wait up to 2 min. |
| `SECRETS_RULES` | do not read any `.env` (located in `$R/meetingagent-local/`), no real mails, do not output secrets; do not send agents into a meeting from the preview. Exception: `$T/sim.py` reads keys itself, mails land in Mailpit |
| `COMMIT_STYLE` | `feat(<area>): …` in German, with `Co-Authored-By` |
| `POST_RUN_HOOK` | `aufgabentracker:wrap` |
| `MODELS` | S: implementer and reviewer `sonnet` · M: implementer per group, reviewer ≥ `sonnet` · L: implementer and reviewer `opus` for logic groups |
