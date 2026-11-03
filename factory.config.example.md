# factory.config.md — Projekt-Adapter für `/factory`

Diese Datei kopierst du als `factory.config.md` in den Session-Ordner `R` (empfohlen:
`$R/factory.config.md`, **außerhalb** des Repos — sonst lesen Implementer im Worktree, wo die
versiegelten Abnahmetests liegen; Fallback `<repo>/.claude/factory.config.md`) und füllst jeden Slot aus. `SKILL.md` und `reviewers.md`
nennen nur die Slot-Namen (`{{TARGET_BRANCH}}` usw.); die Werte stehen ausschließlich hier.
Ein leerer optionaler Slot heißt: dieser Teil des Ablaufs entfällt.

Ein ausgefülltes Beispiel liegt in `examples/meetingagent.factory.config.md`.

---

## 1. Pfade und Repo

| Slot | Bedeutung | Wert |
|---|---|---|
| `SESSION_ROOT` | Ordner, in dem die Claude-Session startet (`R`). Muss den Checkout `M` enthalten und den OpenSpec-Ordner. | `…` |
| `REPO_DIR` | Name des Checkouts unter `R` (`M = $R/$REPO_DIR`), steht auf `TARGET_BRANCH`. | `…` |
| `WORKTREE_PATTERN` | Worktree je Lauf (`W`). | `$R/$REPO_DIR-<slug>` |
| `OPENSPEC_DIR` | Wo `openspec/changes/<slug>` liegt (`S`). | `$R/openspec` |
| `LOCK_DIR` | Sperren und Warteschlange (`L`). | `$R/.factory-locks` |
| `SEALED_ROOT` | Wurzel der versiegelten Abnahmetests (`Z`), **außerhalb** von `R`. | `$HOME/.factory-sealed` |
| `PATH_STYLE` | `posix` oder `windows` (Git-Bash: Pfade mit `pwd -W`, jeder Docker-Pfad mit `MSYS_NO_PATHCONV=1`). | `…` |
| `PROJECT_RULES` | Datei mit Invarianten/Nutzerentscheidungen, die Maßstab für alle Reviewer ist. | `$M/CLAUDE.md` |

## 2. Branches und harte Grenzen

| Slot | Bedeutung | Wert |
|---|---|---|
| `TARGET_BRANCH` | Dorthin pusht die Factory direkt (ohne MR), nach Gate + grünen Tests + Abnahmetests + Review. | `develop` |
| `PROD_BRANCH` | Wird **nie** angefasst (kein Push, kein MR). | `main` |
| `PROTECTED_JOBS` | CI-Jobs/Aktionen, die die Factory nie auslöst. | `…` |
| `FEATURE_BRANCH` | Branch-Muster je Lauf. | `feat/<slug>` |
| `ABORT_PUSH_OK` | Darf ein abgebrochener Lauf den Feature-Branch sichern (`git push origin feat/<slug>`)? Nur ja, wenn auf Feature-Branches keine teuren/deployenden CI-Jobs laufen. | `ja` |
| `PIPELINE_URL` | Link für Protokoll/Report. | `…` |
| `RELEASE_NOTE` | Ein Satz, was nach `TARGET_BRANCH` noch fehlt, bis es live ist (z. B. „live erst nach Release-MR nach main“). | `…` |

Die Ausnahme „Factory pusht direkt nach `TARGET_BRANCH`“ muss in `PROJECT_RULES` stehen,
sonst melden Reviewer sie als Befund.

## 3. Befehle

Jeder Befehl mit `$W` als Platzhalter für den Worktree (wird den Subagents wörtlich eingesetzt).

| Slot | Bedeutung | Wert |
|---|---|---|
| `TEST_FULL` | Volle Suite (schwer, läuft über `queue.sh`). | ```…``` |
| `TEST_FULL_FRESH_DEPS` | Volle Suite mit frischer Abhängigkeits-Installation — nur wenn `DEPS_FILES` im Diff. | ```…``` |
| `TEST_ONE` | Eine Testdatei (leicht, läuft sofort). `<datei>` als Platzhalter. | ```…``` |
| `TEST_LIGHT` | Weitere leichte Suiten (z. B. JS), laufen sofort. | ```…``` |
| `TEST_FULL_LIST` | Wie `TEST_FULL`, aber mit Pass/Fail-Liste je Test (für die Baseline), z. B. `pytest -rA`. | ```…``` |
| `KNOWN_LOCAL_FAILURES` | Tests, die lokal aus bekanntem Grund scheitern und nicht als rot zählen (im Report nennen). | `…` |
| `DEPS_FILES` | Dateien, deren Änderung frische Installation verlangt. | `requirements.txt` |
| `HEAVY_JOBS` | Was **immer** über `queue.sh` läuft (über alle Läufe nacheinander). | volle Suite, Baseline, Image-Builds, Harness-Läufe |

## 4. Abnahmetests (versiegelt)

| Slot | Bedeutung | Wert |
|---|---|---|
| `ACCEPTANCE_STYLE` | Wie die Abnahmetests geschrieben werden: `unit` (gleiche Sprache/Framework wie die Suite, gegen die öffentlichen Schnittstellen aus der Spec), `blackbox` (HTTP/CLI/Browser gegen die laufende Vorschau) oder beides. | `…` |
| `ACCEPTANCE_RUN` | Befehl, der die Tests aus `$Z` gegen `$W` laufen lässt, **ohne** sie in `$W` abzulegen (Read-only-Mount oder Kopie in einen Wegwerf-Container). Ausgabe **nur** Zusammenfassung + Namen roter Tests, keine Tracebacks/Assertions (z. B. `pytest -q --tb=no -rf … 2>&1 \| sed 's/ - .*$//'`). | ```…``` |
| `ACCEPTANCE_TIERS` | In welchen Stufen es versiegelte Abnahmetests gibt. Default `M,L` (bei S optional). | `M,L` |
| `ACCEPTANCE_FEEDBACK` | Was ein Fix-Agent bei roten Abnahmetests sieht: `requirement` (nur Anforderungs-ID + Verhalten erwartet/beobachtet, Default) oder `assertion` (Testname + Assertion-Text + Traceback-Kopf, nie die Testdatei). | `requirement` |
| `ACCEPTANCE_COMMIT_DIR` | Wohin die Tests nach bestandener Abnahme im Repo committet werden (Regressionsschutz). Leer = nicht committen. | `tests/acceptance/` |

## 5. Stufen-Kriterien (S/M/L)

Pfad-Globs und Themen; die höchste zutreffende Stufe gilt, im Zweifel die höhere.

| Slot | Bedeutung | Wert |
|---|---|---|
| `TIER_L` | Kritischer Laufzeitpfad, Rechte/Rollen, Mandantentrennung, Fremd-Input-Parsing, Datenschutz, Migration, öffentliche API. | `…` |
| `TIER_M` | Backend-Änderung, neue/geänderte Route, neues Feld im Datenmodell, Frontend-Logik mit eigenem Zustand/Datenfluss. | `…` |
| `TIER_S` | Nur Darstellung/Texte/Layout im Frontend-Ordner (+ Tests dazu), ohne neue Daten oder Abfragen. | `…` |
| `TIER_MINUTES` | Grobe Dauer je Stufe für die Gate-Anzeige. | `S ~10 min, M ~30 min, L 1–2 h` |

## 6. Reviewer-Zuständigkeit

| Slot | Reviewer | zuständig, wenn eine geänderte Datei passt | Wert |
|---|---|---|---|
| `REVIEW_SECURITY` | Security (§2) | Default: immer (außer S — dort prüft UI/UX die Frontend-Punkte mit) | `immer` |
| `REVIEW_RUNTIME` | Laufzeit/kritischer Pfad (§1) | Pfade, die in ein ausgeliefertes Artefakt gehen (Image, Binary, Worker, Mobile-Build …) | `…` |
| `REVIEW_UI` | UI/UX voll (§4) | Frontend-Ordner | `…` |
| `REVIEW_UI_TEXT` | UI/UX nur Texte (§4.5) | Kundentexte im Backend (Fehlermeldungen, Mail-Texte) | `…` |
| `REVIEW_DEPS` | Abhängigkeiten, Nachprüfung (§3) | Diff berührt Dateien, die in `tasks.md` nicht vorkommen | `immer laut Regel` |

Zusätzliche, projekt­spezifische Prüfpunkte je Reviewer:

```
SECURITY_EXTRA:
- …   (z. B. „Bot-Zugriff nur über accounts.require_bot, fremder Datensatz → 404, nie 403“)
RUNTIME_EXTRA:
- …   (z. B. „neues Feld erreicht den Container: beide Runner + fetch_config“)
DEPS_EXTRA:
- …   (z. B. „CI-Pfadfilter in .gitlab-ci.yml“)
UI_EXTRA:
- …   (z. B. „Kundentexte: du-Form, keine Interna“)
SECURITY_ROLES: <Rollen-Matrix je Route, z. B. anonym, Mitglied, fremde Org, Admin, Superadmin, API-Token>
CONFLICT_ORDER: Projektregeln > Security > Laufzeit-Qualität > Abhängigkeiten > Optik
```

## 7. Laufzeit-Artefakt (optional, nur wenn `REVIEW_RUNTIME` gesetzt)

| Slot | Bedeutung | Wert |
|---|---|---|
| `ARTIFACT_BUILD` | Artefakt aus `$W` bauen (schwer, über `queue.sh`), Tag mit Slug. | ```…``` |
| `ARTIFACT_BUILD_BASE` | Dasselbe aus dem Basis-Worktree, Tag `base-<B>` (wird zwischen Läufen auf gleicher Basis geteilt). | ```…``` |
| `ARTIFACT_IMPORT_CHECK` | Smoke im gebauten Artefakt (z. B. Import aller geänderten Module). | ```…``` |
| `ARTIFACT_LOCAL_REFRESH` | Was nach dem Push das lokal genutzte Artefakt aktualisiert (sonst testet der Nutzer live den alten Stand). | ```…``` |
| `RUNTIME_CORE_FUNCTIONS` | Kernfunktionen, die je Punkt durch grünen Test belegt oder begründet unberührt sein müssen. | Liste |
| `LIVE_CHECKLIST_ALWAYS` | Punkte, die immer auf der Live-Checkliste stehen (was keine lokale Prüfung abdeckt). | Liste |
| `LIVE_STATUS_PATHS` | Diff berührt diese → Status „gepusht – Live-Test offen“, nie „fertig“. | `…` |

## 8. Szenario-Harness (optional)

Eine Attrappe/Simulator, gegen die das echte Artefakt läuft (End-to-End). Leer = entfällt.

| Slot | Bedeutung | Wert |
|---|---|---|
| `HARNESS_DIR` | Ordner (`T`), außerhalb des Repos. | `…` |
| `HARNESS_STD_SCENARIOS` | Standard-Set, läuft bei jedem Lauf mit Laufzeit-Pfaden. | `…` |
| `HARNESS_RUN` | `<image> <szenarien> -n <N>` | ```…``` |
| `HARNESS_COMPARE` | Vergleich Basis vs. Lauf mit Nachmessen; Exit 1 = Rückschritt. | ```…``` |
| `HARNESS_SCENARIO_FILE` | Wo neue Lauf-Szenarien hinkommen (nicht committet). | `$T/scenarios_<slug>.py` |
| `HARNESS_NOTES` | Bekannte Fallen (Encoding, Logs zuerst lesen …). | `…` |

## 9. Vorschau-Instanz (optional, für UI-Änderungen)

| Slot | Bedeutung | Wert |
|---|---|---|
| `PREVIEW_TRIGGER` | Pfade, die eine Vorschau verlangen. | `…` |
| `PREVIEW_PORTS` | Portbereich, erster freier wird genommen. | `8081-8099` |
| `PREVIEW_START` | Startbefehl (`<slug>`, `$P`, `$W` als Platzhalter), eigene Kopie der Daten, Hot-Reload. | ```…``` |
| `PREVIEW_SEED` | Wie synthetische Testdaten geladen werden (Normalfall, Leerzustand, Lang-Text mit `<img onerror>`). | `…` |
| `SHARED_INSTANCE` | Gemeinsame Instanz anderer Sessions (Vorher-Screenshots), **nur lesen**. | `http://127.0.0.1:8080` |
| `SHARED_INSTANCE_DONTS` | Was dort verboten ist (Logout, schreibende Requests …) und warum. | `…` |
| `SCREENSHOT_TOOL` | Headless-Screenshot-Werkzeug, das parallel laufen kann (nicht der geteilte Playwright-MCP). | `…` |
| `SCREEN_WIDTHS` | Breiten. | `1280 390` |
| `STYLE_SOURCE` | Styleguide/Komponenten, an denen sich Neues messen muss. | `…` |
| `CLEANUP` | Was Schritt 8 entfernt (Container, Volumes, Images, Basis-Worktree, Seed-Daten). | Liste |

## 10. Preflight und Sonstiges

| Slot | Bedeutung | Wert |
|---|---|---|
| `PREFLIGHT` | Liste von Prüfungen, die alle stimmen müssen (Remote erreichbar, Werkzeuge da, Instanz antwortet …). | Liste |
| `AUTOSTART` | Befehle, die fehlende Laufzeit-Voraussetzungen selbst starten (Docker Desktop, `docker compose up -d` …), je mit Wartezeit. | leer |
| `SECRETS_RULES` | Was nie gelesen/ausgegeben wird (`.env` …), Ausnahmen. | `…` |
| `COMMIT_STYLE` | Commit-Stil + Sprache. | `feat(<bereich>): …` + `Co-Authored-By` |
| `POST_RUN_HOOK` | Optionaler Skill/Befehl nach dem Report (z. B. Status an Aufgabentracker). | leer |
| `MODELS` | Modellwahl je Stufe (Implementer/Reviewer). | `S: sonnet · M: Reviewer ≥ sonnet · L: opus für Logik` |
