# factory.config.md — Beispiel: MeetingAgent (Ursprungsprojekt)

Ausgefüllter Adapter des Projekts, in dem die Factory entstanden ist: FastAPI-WebUI
(Control-Host) + Bot-Container (Teams-Meeting-Agent), Windows/Git-Bash, Docker, GitLab.
Zeigt, wie konkret die Slots gemeint sind.

## 1. Pfade und Repo

| Slot | Wert |
|---|---|
| `SESSION_ROOT` | `meetingagent-neu/` (enthält `MeetingAgent/` und `openspec/`) |
| `REPO_DIR` | `MeetingAgent` — Checkout auf `develop`, Mount der lokalen Instanz :8080 |
| `WORKTREE_PATTERN` | `$R/MeetingAgent-<slug>` |
| `OPENSPEC_DIR` | `$R/openspec` |
| `LOCK_DIR` | `$R/.factory-locks` |
| `SEALED_ROOT` | `$HOME/.factory-sealed` |
| `PATH_STYLE` | `windows` |
| `PROJECT_RULES` | `$M/CLAUDE.md` |

## 2. Branches und harte Grenzen

| Slot | Wert |
|---|---|
| `TARGET_BRANCH` | `develop` |
| `PROD_BRANCH` | `master` |
| `PROTECTED_JOBS` | `bot_image_latest` (setzt `:latest` der ganzen Kundenflotte), `deploy_config`, `bot_smoke` |
| `FEATURE_BRANCH` | `feat/<slug>` |
| `ABORT_PUSH_OK` | ja — auf Feature-Branches läuft nur `pytest`, keine Fly-Jobs |
| `PIPELINE_URL` | `https://gitlab.usecaise.net/usecaise-platform/meetingagent/-/pipelines?ref=develop` |
| `RELEASE_NOTE` | `develop` baut kein Bot-Image und deployt die WebUI nicht — live erst mit dem Release nach `master` (`bot_image` → `bot_smoke` → `bot_image_latest`). |

## 3. Befehle

```bash
# TEST_FULL (Image der lokalen Instanz hat requirements + pytest)
MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/src:ro" -e WEBUI_SECRET=ci-secret meetingagent-local-webui:latest \
  sh -c "cp -r /src /app && cd /app && python -m pytest -q -p no:cacheprovider"
# TEST_FULL_FRESH_DEPS (nur wenn requirements.txt im Diff)
MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/src:ro" -e WEBUI_SECRET=ci-secret python:3.12-slim \
  sh -c "cp -r /src /app && cd /app && pip install -q -r requirements.txt && python -m pytest -q -p no:cacheprovider"
# TEST_ONE
… python -m pytest -q -p no:cacheprovider tests/<datei>.py
# TEST_LIGHT (JS)
MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/w" -w /w node:22 sh -c "node --test webui/static/*.test.js"
# TEST_FULL_LIST
wie TEST_FULL mit `-rA`
```

| Slot | Wert |
|---|---|
| `KNOWN_LOCAL_FAILURES` | `test_preview_uses_the_bot_file` (nur CRLF unter Windows) |
| `DEPS_FILES` | `requirements.txt` |
| `HEAVY_JOBS` | volle Python-Suite (auch Baseline und Suiten der Reviewer), Bot-Image-Build, Simulator-Läufe (feste Container `teams-sim`/`bot-sim`, nur einer zur Zeit) |

## 4. Abnahmetests

| Slot | Wert |
|---|---|
| `ACCEPTANCE_STYLE` | `unit` (pytest gegen die Schnittstellen aus `design.md`, Server per FastAPI-TestClient) + bei UI `blackbox` (Headless-Chrome gegen die Vorschau `:$P`) |
| `ACCEPTANCE_RUN` | ```MSYS_NO_PATHCONV=1 docker run --rm -v "$W:/src:ro" -v "$Z:/acc:ro" -e WEBUI_SECRET=ci-secret meetingagent-local-webui:latest sh -c "cp -r /src /app && cp -r /acc /app/tests/_acceptance && cd /app && python -m pytest -q -p no:cacheprovider tests/_acceptance"``` |
| `ACCEPTANCE_TIERS` | `M,L` |
| `ACCEPTANCE_FEEDBACK` | `requirement` |
| `ACCEPTANCE_COMMIT_DIR` | `tests/acceptance/<slug>/` |

## 5. Stufen-Kriterien

| Slot | Wert |
|---|---|
| `TIER_L` | `core/`, `docker/` oder ein anderer Bot-Image-Pfad; Sprache, Gate, TTS, Prompt; Rechte/Rollen (`accounts`, `require_bot`, Stufen, Freigaben, Org-Token); Mandantentrennung; Fremd-Input-Parsing (Mails, .ics, Uploads); neuer Speicherort für Meetingdaten oder Datenschutz-Pfad (`purge_window`, Opt-out, `effective_meeting_sources`); Migration von Bestandsdaten; Integrations-API `/api/v1` |
| `TIER_M` | ein `webui/*.py` ändert sich; neue oder geänderte Route; neues Feld in einem Store; Frontend-Logik mit eigenem Zustand, Routing oder Datenfluss (Deep-Link, Autosave, neue API-Abfrage) |
| `TIER_S` | nur Darstellung, Texte, Layout oder Umbau bestehender Ansichten in `webui/static/` (und Tests dazu), ohne neue Daten oder Abfragen |
| `TIER_MINUTES` | S ~10 min, M ~30 min, L 1–2 h |

## 6. Reviewer-Zuständigkeit

| Slot | Wert |
|---|---|
| `REVIEW_SECURITY` | immer (außer S) |
| `REVIEW_RUNTIME` | `core/`, `docker/`, `Dockerfile`, `bin/start_chromium_cdp.sh`, `prompts/system.md`, `requirements.txt`, `fly.toml`, `pyproject.toml`, oder ein `webui/*.py`, das `.dockerignore` **nicht** ausschließt — maßgeblich ist die aktuelle `.dockerignore` |
| `REVIEW_UI` | `webui/static/` oder `core/avatar.js` |
| `REVIEW_UI_TEXT` | Kundentext in `webui/*.py` (`detail=`, `HTTPException`, `FieldError`, `LAUNCH_ERRORS`, Mail-Texte) |

```
SECURITY_ROLES: anonym, Mitglied, Mitglied fremder Org, org_admin, Betreiber-Superadmin, Org-Token, Bot-Token
SECURITY_EXTRA:
- Bot-Zugriff nur über accounts.require_bot(bot_id, user, level) mit richtiger Stufe
  (read/content/write/admin/own); fremder Agent → 404, nie 403.
- Superadmin hat nur read + admin, kein write/content. Org-Token-Regeln aus CLAUDE.md.
- tests/test_route_guard.py grün und MIN_ROUTES noch passend.
- Konto-Mails mit record=False.
- Neuer Speicherort für Meetingdaten → purge_window und purge_bot_data; Audit-Zeile.
RUNTIME_EXTRA:
- Neues Feld erreicht den Container: beide Runner (_run_args, _bot_launch_config) und fetch_config.
- Import-Check: docker run --rm --entrypoint /opt/venv/bin/python -w /srv/teams-meeting-bot/core
  meetingagent-local-bot:factory-<slug> -c "import <module>"
DEPS_EXTRA:
- Neues Agent-Feld: bots_store.check_fields, beide Runner, core/fetch_config.py, /api/v1 (Schema,
  alte Clients), Vorlagen, Assistent, Default für Bestandsdaten.
- Ops-Knopf: container_runner._PASS_ENV ↔ server._OPS_ENV; Pro-Bot-Felder NICHT dort.
- core/ importiert Neues → .dockerignore und test_audit_fixes.py.
- Alte Bot-Images in Prod (:latest wird manuell gezogen): Host mit altem Bot und umgekehrt.
- CI-Pfadfilter in .gitlab-ci.yml (neue webui/static/*.test.js → Job frontend_test;
  neue Bot-Image-Pfade → .bot_image_changes); requirements.txt/requirements.lock synchron.
- DE/EN-Texte; TestCustomerWording.
UI_EXTRA:
- Kundentexte: „du“, keine Interna (Liste in CLAUDE.md „Kundentexte“), nur Teams als Plattform.
CONFLICT_ORDER: CLAUDE.md-Invarianten > Security > Bot-Qualität > Abhängigkeiten > Optik
```

## 7. Laufzeit-Artefakt (Bot-Image)

| Slot | Wert |
|---|---|
| `ARTIFACT_BUILD` | `docker build -t meetingagent-local-bot:factory-<slug> "$W"` (teilt den Cache mit `docker compose build bot`) |
| `ARTIFACT_BUILD_BASE` | `docker build -t meetingagent-local-bot:base-$B "$W-base"` (nur wenn `docker image inspect` es nicht findet) |
| `ARTIFACT_IMPORT_CHECK` | siehe `RUNTIME_EXTRA` |
| `ARTIFACT_LOCAL_REFRESH` | `docker compose -f "$R/meetingagent-local/compose.yml" build bot` (Image `meetingagent-local-bot:latest`, das „Ins Meeting schicken“ auf :8080 startet); laufende Bots: „Meeting verlassen“ und neu schicken |
| `RUNTIME_CORE_FUNCTIONS` | Beitritt, Lobby, automatisches Verlassen, Teardown über `finish_meeting` (auch SIGTERM) · KI-Hinweis im Chat, Anzeigename „- KI“, Opt-out per „OUT“ und per Zuruf · Sprech-Gate: Antwort auf Namen, kein Reinreden ohne Anlass, `REPLY_MAX`, Followup · Ansage durch das Werkzeug, Werkzeug-Ergebnis wird gesprochen · Szenarien über mehrere Turns (zwei Fragen hintereinander, Frage während der Bot spricht, Ansprache nach fremdem Gespräch, Satz mit Datum und Zahl) · Zusammenfassung und Mail, Glossar, `MEETING_SOURCES`, Sprecher-Zuordnung · synchrones I/O in Tools in `asyncio.to_thread` |
| `LIVE_CHECKLIST_ALWAYS` | echtes Teams-DOM (Selektoren), Echo über die Lautsprecher der Teilnehmer, echte Netzlatenz; nach dem Release `master` → `bot_smoke` im Teams-Meeting |
| `LIVE_STATUS_PATHS` | Bot-Image-Pfade, Sprache, Gate, Prompt, Werkzeuge |

## 8. Szenario-Harness (Teams-Simulator)

| Slot | Wert |
|---|---|
| `HARNESS_DIR` | `$R/meetingagent-local/teamssim` — echter Bot-Container gegen eine Teams-Attrappe (Beitritt, Lobby, Roster, Chat/Opt-out, Sprache, Verlassen, Zusammenfassungs-Mail in Mailpit) |
| `HARNESS_STD_SCENARIOS` | `s3_direkt s5_nachfrage s6_diskussion s7_unterbrechen t3_optout t5_ende` |
| `HARNESS_RUN` | `bash "$K/queue.sh" "$L" <slug>-sim <ausgabe> env PYTHONIOENCODING=utf-8 python "$T/sim.py" run factory-<slug> <szenarien> -n 2` |
| `HARNESS_COMPARE` | `env PYTHONIOENCODING=utf-8 python "$T/sim.py" compare base-$B factory-<slug> <szenarien> --nachmessen` → `$T/out/compare-base-$B-vs-factory-<slug>.md`; Exit 1 = Rückschritt |
| `HARNESS_SCENARIO_FILE` | `$T/scenarios_<slug>.py` (`SCENARIOS = {...}`, optional `VOICES`; `sim.py` lädt die Datei selbst) |
| `HARNESS_NOTES` | Ein Lauf ≈ 1,5 min. Fehlt `result.json`, ist der Bot meist nie beigetreten → zuerst `$T/out/<lauf>/bot.log`. `sim.py` liest Provider-Keys selbst aus der `.env` (nie ausgeben). Das zuletzt gelaufene Sim-Image hängt am geteilten `bot-sim`-Container und lässt sich nicht ohne Zwang entfernen. |

## 9. Vorschau-Instanz

| Slot | Wert |
|---|---|
| `PREVIEW_TRIGGER` | `webui/static/` oder `core/avatar.js` |
| `PREVIEW_PORTS` | `8081-8099` |
| `SHARED_INSTANCE` | `http://127.0.0.1:8080` |
| `SHARED_INSTANCE_DONTS` | kein Logout (`/api/logout` entwertet per `bump_epoch` alle Sitzungen des Demo-Kontos), keine POST/PUT/PATCH/DELETE, nichts anlegen oder speichern; keine Agenten ins Meeting schicken |
| `SCREENSHOT_TOOL` | `meetingagent-neu/.playwright-mcp/shot.mjs` (Env `BASE`, `CDP_PORT`; legt Bilder neben sich ab, gibt Konsolenfehler aus) |
| `SCREEN_WIDTHS` | `1280 390` |
| `STYLE_SOURCE` | UseCaise-Styleguide (styleguide.usecaise.net: Tokens, Fonts, uc-Komponenten) + bestehende WebUI-Komponenten |

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
# Docker-Socket braucht /api/fleet (sonst „Verbindung gestört“). requirements.txt im Diff →
# vor uvicorn `pip install -r ../requirements.txt` (sh -c).
```

`PREVIEW_SEED`: Konten/Agenten/Einladungen kommen aus der Kopie von `state/`, Meetings und
Transkripte **nicht** (`transcripts/` ist im Worktree leer, gitignored). Seed-Skript
`$W/transcripts/seed_<slug>.py` über `meeting_knowledge_store.add_meeting` /
`invites_store.upsert_invite`, laden per
`MSYS_NO_PATHCONV=1 docker exec factory-<slug>-webui python /srv/teams-meeting-bot/transcripts/seed_<slug>.py`.

`CLEANUP`: `docker rm -f factory-<slug>-webui`, `docker volume rm factory-<slug>-state`,
`docker rmi meetingagent-local-bot:factory-<slug>`, Seed-Daten in `$W/transcripts/`.

## 10. Preflight und Sonstiges

| Slot | Wert |
|---|---|
| `PREFLIGHT` | `curl -sI http://127.0.0.1:8080/` antwortet; `openspec`, `node`, `docker` vorhanden |
| `SECRETS_RULES` | keine `.env` lesen (liegt in `$R/meetingagent-local/`), keine echten Mails, keine Secrets ausgeben; in der Vorschau keine Agenten ins Meeting schicken. Ausnahme: `$T/sim.py` liest Keys selbst, Mails landen in Mailpit |
| `COMMIT_STYLE` | `feat(<bereich>): …` auf Deutsch, mit `Co-Authored-By` |
| `POST_RUN_HOOK` | `aufgabentracker:wrap` |
| `MODELS` | S: Implementer und Reviewer `sonnet` · M: Implementer je Gruppe, Reviewer ≥ `sonnet` · L: Implementer und Reviewer `opus` für Logik-Gruppen |
