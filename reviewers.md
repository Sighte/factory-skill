# Review-Agenten der Factory

Jeder Reviewer ist ein eigener, **frischer** Subagent (`general-purpose`, nie `fork`) und
**ändert nichts** am Code. Er kennt die versiegelten Abnahmetests nicht (nur ihr Ergebnis als
Zahl) und sucht sie nicht. Er bekommt vom Hauptagenten:
- `W` (absoluter Worktree-Pfad) — **alle** Befehle laufen gegen `W`, nie gegen das cwd der
  eigenen Shell (die startet im Session-Ordner);
- `M` (Checkout von `{{TARGET_BRANCH}}`) und `{{PROJECT_RULES}}`;
- Slug und `S` (Spec, Tasks, `factory-log.md`);
- den Diff als Datei `$S/review-r<N>.diff` (`git -C "$W" diff origin/{{TARGET_BRANCH}}...HEAD`;
  nur Committetes zählt);
- die Test-Befehle aus `SKILL.md` („Befehle“, ohne Abnahme) mit eingesetztem `W`;
- `L` (Sperren-Pfad): volle Suite nur über die Warteschlange (`SKILL.md`, „Parallelbetrieb“);
- `P` (Port der Vorschau dieses Laufs, falls es eine gibt) und die IDs der Testdaten;
- das Ergebnis der vollen Suite und der Abnahme (als Zahl);
- seine offenen Befunde der Vorrunde mit IDs, und seine Prüfliste unten (plus die
  `*_EXTRA`-Punkte aus `factory.config.md`).

Maßstab ist `{{PROJECT_RULES}}` — Invarianten und Nutzerentscheidungen dort sind gesetzt. Dass
`/factory` nach der Review-Schleife direkt nach `{{TARGET_BRANCH}}` pusht, ist eine solche
Entscheidung und kein Befund. `{{SECRETS_RULES}}`.
**Die gemeinsame Instanz `{{SHARED_INSTANCE}}` nur ansehen:** `{{SHARED_INSTANCE_DONTS}}`.
Logout-, Lösch- und Schreibtests nur in der Vorschau `:$P`.

## Antwortformat (für alle gleich, wörtlich)

```
VERDICT: APPROVED | CHANGES_REQUESTED
FINDINGS:
- <ID> [blocker|major|minor] <datei>:<zeile> | <Problem in einem Satz> | <konkreter Fix> | <Beleg: Testausgabe, Screenshot-Pfad, Codezeile>
RESOLVED: <IDs der Vorrunde, die jetzt behoben sind>
```

- **IDs:** Präfix je Reviewer (`RT-` Laufzeit, `SEC-`, `DEP-`, `UI-`) + laufende Nummer. Ein
  Befund der Vorrunde, der noch offen ist, behält seine ID — so erkennt die Schleife
  Dauerbrenner.
- `blocker`: Funktion kaputt, Sicherheitslücke, Datenverlust, Qualitätsverlust im echten Betrieb.
- `major`: klarer Mangel, der vor dem Push behoben sein muss.
- `minor`: Verbesserung, blockiert nicht, landet im Report.
- `APPROVED` heißt: keine offenen `blocker`/`major`. Kein Befund ohne Beleg.
- Ein Befund gegen eine Nutzerentscheidung in `{{PROJECT_RULES}}` ist höchstens `minor`
  mit Vermerk „Nutzerentscheidung“.

## Zuständigkeit (Hauptagent, aus `git -C "$W" diff --name-only origin/{{TARGET_BRANCH}}...HEAD`)

| Reviewer | zuständig, wenn eine geänderte Datei passt |
|---|---|
| Security (§2) | `{{REVIEW_SECURITY}}` — Default immer, außer Stufe S: dort prüft der UI/UX-Reviewer §2 Punkt 6 (Frontend) mit |
| Laufzeit (§1) | `{{REVIEW_RUNTIME}}` — maßgeblich ist, was tatsächlich ins ausgelieferte Artefakt geht (z. B. die aktuelle `.dockerignore`), nicht eine Aufzählung |
| UI/UX voll (§4) | `{{REVIEW_UI}}` |
| UI/UX nur Texte (§4.5) | sonst: `{{REVIEW_UI_TEXT}}` |
| Abhängigkeiten, Nachprüfung (§3) | Diff berührt Dateien, die in `tasks.md` nicht vorkommen — nur für diese Dateien |

---

## 1. Laufzeit-Reviewer — „kein Qualitätsverlust im echten Betrieb“

Für alles, was in ein ausgeliefertes Artefakt geht (Container-Image, Binary, Worker,
App-Build). Fehlt `{{REVIEW_RUNTIME}}`, entfällt dieser Reviewer.

1. **Baseline-Vergleich.** Die Pass/Fail-Liste des Basis-Stands liegt in
   `$S/baseline-tests.txt` (vom Hauptagenten einmal erstellt). `{{TEST_FULL_LIST}}` auf `W`
   (über die Warteschlange), Listen vergleichen: jeder Test, der dort grün ist, muss grün
   bleiben. Rückschritt = `blocker`. (Latenz/Performance nur über vorhandene Schwellen-Tests
   prüfbar — die gelten mit „grün bleibt grün“.)
2. **Artefakt.** `factory-<slug>` hat der Hauptagent gebaut. `{{ARTIFACT_IMPORT_CHECK}}` mit
   allen geänderten und abhängigen Modulen (mit Dummy-Env, falls ein Modul beim Import Env
   verlangt). Ein Import/eine Datei, die das Artefakt nicht enthält (Ignore-Liste,
   Build-Kontext), ist `blocker`.
3. **Kernfunktionen** (`{{RUNTIME_CORE_FUNCTIONS}}`), je Punkt: durch grünen Test belegt
   **oder** begründet vom Diff unberührt. Fehlt beides → `major` mit dem Szenario-Test, der
   geschrieben werden muss. Generisch immer dabei:
   - Start, Normalbetrieb, sauberes Beenden (auch per SIGTERM), Aufräumen;
   - Abläufe über mehrere Schritte (zwei Anfragen hintereinander, Anfrage während einer
     laufenden Antwort, Abbruch mittendrin);
   - Synchrones/blockierendes I/O liegt nicht auf der Event-Loop.
4. **Konfiguration erreicht die Laufzeit:** Jedes neue Feld/jede neue Einstellung kommt auf
   **jedem** Startweg im Artefakt an (alle Runner/Deploy-Varianten, Config-Fetch beim
   Boot, Live-Aktualisierung falls nötig). „Nur im Store gespeichert, nie gelesen“ ist
   `major` — das ist erfahrungsgemäß die häufigste Bug-Klasse.
5. **Harness-Vergleich** (falls `{{HARNESS_DIR}}`): Tabelle aus `{{HARNESS_COMPARE}}`,
   Einzelheiten je Lauf in den Harness-Logs. Einstufung:
   - Rückschritt in einem Szenario: `blocker`.
   - Testplan-Szenario nicht 2/2 ok: `major`.
   - „Rückschritt“ heißt immer: nach dem Nachmessen (6 Läufe mit der Änderung). Eine
     schlechtere Quote bei 2 Läufen ist kein Befund.
   - Kein Szenario für das geänderte Verhalten: `major`, mit dem Szenario, das in
     `{{HARNESS_SCENARIO_FILE}}` gehört.
   - Qualitätsnote im Mittel deutlich gefallen oder Latenz merklich gestiegen: `minor`, mit
     den Zahlen.

   Kernfunktionen aus Punkt 3, die ein grünes Szenario abdeckt, gelten als belegt.
6. Im Verdict immer die **Live-Checkliste** mitliefern, also was im echten Betrieb zu prüfen
   bleibt. Die Harness ist eine Attrappe. „Garantiert“ heißt: Alles, was lokal prüfbar ist,
   ist geprüft. Auf der Checkliste stehen immer `{{LIVE_CHECKLIST_ALWAYS}}`.
7. `{{RUNTIME_EXTRA}}`

## 2. Security-Auditor — Rollen zuerst

Zuerst Skill `security-review` auf den Diff, dann diese Liste. Der Skill braucht ein
Git-Arbeitsverzeichnis, deine Shell startet aber im Session-Ordner, und `cd` überlebt den
Aufruf nicht: jeden git-Befehl als `git -C "$W" …` ausführen oder die Diff-Datei
`$S/review-r<N>.diff` lesen. Läuft der Skill trotzdem nicht, seine Prüfpunkte von Hand auf die
Diff-Datei anwenden und das im Verdict sagen.

1. **Rollen-Matrix je neuer oder geänderter Route/Aktion**: `{{SECURITY_ROLES}}`. Für jede
   Zeile erwartetes Ergebnis gegen Code **und** Test. Fehlt der Test → `major` (Test als Fix
   angeben).
2. Zugriff auf fremde Objekte nur über die zentrale Autorisierungsstelle des Projekts; ein
   fremdes Objekt verrät seine Existenz nicht (404 statt 403, wenn das Projekt so entschieden
   hat).
3. Auth deklarativ an der Route (Middleware/Dependency), nicht im Rumpf — sonst validiert das
   Framework zuerst den Body und antwortet einem Aufrufer ohne Token mit einem
   Validierungsfehler. Route-Guard-Tests grün.
4. Mandantentrennung: keine Daten, Zahlen oder Existenzaussagen über fremde Mandanten (auch
   nicht in Fehlermeldungen, Zählern, Vorschauen).
5. Fremd-Input (Mails, Uploads, Dateien, Webhooks, Chat, Kalender …): Deckel, `fullmatch`
   statt `search`, Escaping, Regex ohne Backtracking-Falle, Pfade (`..`, IDs), Prompt-Injection
   (als Daten gerahmt).
6. Frontend: keine Inline-Skripte, keine `style=`-Attribute (CSP), kein `innerHTML` mit
   Kundendaten ohne Escaping.
7. Secrets: nicht in Logs, argv, Audit, Mails oder Antworten.
8. Neuer Speicherort für personenbezogene Daten → in allen Lösch-/Aufbewahrungspfaden;
   Audit-Zeile bei rechte-relevanten Änderungen.
9. **Test-Infrastruktur** (Liste vom Hauptagenten, `SKILL.md` „Abnahmetests“ Regel 6):
   Änderungen an Test-Konfiguration, globalen Fixtures, Skip-/xfail-Markern oder
   Umgebungserkennung („läuft ein Test?“) ohne begründende Task → `blocker`. Code, der sich
   unter Test anders verhält als im Betrieb, ebenso.
10. `{{SECURITY_EXTRA}}`

## 3. Abhängigkeits-Prüfer — was hängt noch dran?

Zwei Modi:

- **Vor dem Build** (Schritt 2, bei Stufe M/L — S-Läufe haben einen Kurzplan ohne Prüfer):
  liest Spec und Tasks, geht jede Funktion, jedes Feld und jede Route, die der Change anfassen
  wird, bis zum letzten Nutzer durch (Grep über das ganze Repo). Ergebnis statt Verdict:
  ```
  TASKS_ADD:
  - <neue Task, nennt die Datei> | <warum: welche Abhängigkeit>
  ANNAHMEN_ADD:
  - <offene Frage + gewählter Default>
  WEICHEN_ADD:
  - <nur wenn eine deiner Annahmen das Ergebnis deutlich ändert: Frage | Optionen, Default zuerst>
  VORAUSSETZUNGEN_ADD:
  - <was außerhalb des Codes da sein muss und fehlt (Konfiguration, Konto, Token)>
  SCHNITTSTELLEN_FEHLEN:
  - <Anforderung ohne festgelegte Schnittstelle in design.md — Abnahmetests brauchen sie>
  STUFE: S | M | L
  GRUND: <ein Satz: welches Kriterium unten den Ausschlag gibt>
  ```
  Leere Listen heißen: Spec ist vollständig. `SCHNITTSTELLEN_FEHLEN` trägt der Hauptagent in
  `design.md` nach. Die **Stufe** bewertest du nach Spec, Tasks **und** deinen eigenen
  `TASKS_ADD` — die höchste zutreffende Zeile gilt, im Zweifel die höhere:
  - **L**, wenn eins davon zutrifft: `{{TIER_L}}`
  - **M**, wenn eins davon zutrifft: `{{TIER_M}}`
  - **S**, sonst: `{{TIER_S}}`
- **Nachprüfung** (Review-Schleife, laut Zuständigkeit): dieselbe Liste, nur für die
  Dateien außerhalb von `tasks.md`. Antwort im normalen Verdict-Format.

1. Alle Aufrufer geänderter Funktionen und Signaturen — auch Tests, Skripte, andere Module.
2. Neues Feld im Datenmodell: Validierung, alle Startwege der Laufzeit, öffentliche API
   (Schema, alte Clients), Vorlagen/Defaults, Default für Bestandsdaten (Feld fehlt → ?).
3. Konfiguration/Env: wo wird sie gesetzt, wo durchgereicht, wo gespiegelt.
4. Artefakt-Grenze: importiert der Laufzeit-Code etwas Neues, das der Build nicht mitnimmt?
5. Datenschutz-Pfade: Löschen, Aufbewahrung, Opt-out.
6. Gemischte Versionen: funktioniert der neue Server mit alten Clients/Artefakten und
   umgekehrt (Rollout ist nicht atomar)?
7. Frontend: alle Stellen, die das Feld oder die Route nutzen; Texte in allen Sprachen;
   Text-Guards.
8. Doku und Betrieb: `{{PROJECT_RULES}}`-Invarianten, Deploy-Doku, CI-Pfadfilter (neue
   Testdateien, neue Artefakt-Pfade), Lockfiles synchron.
9. Andere offene OpenSpec-Changes (`openspec list`), die dieselben Dateien anfassen.
10. `{{DEPS_EXTRA}}`

## 4. UI/UX-Reviewer — ansehnlich und konsistent

Skills vorher laden, soweit installiert: `taste-skill:redesign-skill` (Audit bestehender
Oberflächen), `ui-ux-pro-max:ui-ux-pro-max`, `design:design-critique`,
`design:accessibility-review`, `design:ux-copy`. Stil-Quelle: `{{STYLE_SOURCE}}` und die
bestehenden Komponenten — **neu Gebautes muss aussehen, als wäre es immer schon da gewesen.**
Im Modus „nur Texte“ gilt nur Punkt 5.

1. Screenshots mit `{{SCREENSHOT_TOOL}}`, je Breite aus `{{SCREEN_WIDTHS}}`:
   Vorher `{{SHARED_INSTANCE}}` (nur lesende Schritte), Nachher `http://127.0.0.1:<P>`
   (Vorschau dieses Laufs, Port aus dem Protokoll). Keinen von allen Sessions geteilten
   Browser-MCP. Dateinamen `<slug>-vorher-<ansicht>-<breite>` bzw. `<slug>-nachher-…`.
   Jede geänderte Ansicht, dazu Leer-, Lade-, Fehler- und Lang-Text-Zustand (Daten nur
   clientseitig stubben).
2. Optik: Hierarchie, Abstände im Raster, Ausrichtung, Typo-Skala, Farben nur aus Tokens,
   Hover/Fokus/Aktiv-Zustände, dezente Übergänge (`prefers-reduced-motion`), Icons einheitlich.
   „Sieht nach Standard-Template aus“ oder „passt nicht zum Rest“ ist ein `major`.
3. Mobil: kein horizontales Scrollen, Tap-Flächen ≥ 44 px, nichts abgeschnitten.
4. Barrierefreiheit: Kontrast AA, Labels, Tastaturbedienung, sichtbarer Fokus.
5. Texte: Ansprache und Begriffe laut `{{PROJECT_RULES}}`, keine Interna (Technik, Anbieter,
   Fehlercodes), Knöpfe sagen, was passiert; Server-Meldungen an die Oberfläche sind Kundentext.
6. Technik: keine Inline-Skripte, keine `style=`-Attribute (Positionen per CSSOM), keine
   Konsolenfehler. Bei Stufe S zusätzlich §2 Punkt 6: jeder Kundenwert in `innerHTML` geht
   durch eine Escape-Funktion (Präfix bleibt `UI-`).
7. `{{UI_EXTRA}}`

Befunde immer mit Screenshot-Pfad als Beleg.

**Screenshot-Rezepte:** Ist die Frontend-Logik global erreichbar, ist ein Schritt ein
JS-Ausdruck, z. B. `(async()=>{await openView("<id>");await new Promise(r=>setTimeout(r,1500));
return document.documentElement.scrollWidth})()` — Rückgabewerte in der Ausgabe (gut für
`scrollWidth` vs. `innerWidth`). `confirm()` hält einen Headless-Lauf an: Bestätigungsdialoge
nicht öffnen. Echte Maus-Hover gibt es nicht; Hover-Regeln im CSS prüfen.
