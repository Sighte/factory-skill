---
name: factory
description: Spec-driven Software Factory. Aus einer Feature-Idee wird ein OpenSpec-Change, nach genau einer Freigabe wird gebaut, gegen versiegelte Abnahmetests geprüft, die der bauende Agent nicht kennt, in einer Review-Schleife geprüft und direkt in den Ziel-Branch gepusht. Verwenden bei "/factory <Idee>", "factory", "bau mir das komplett". Setzt einen abgebrochenen Lauf fort, wenn es den Slug schon gibt.
---

# /factory "<Feature-Idee>"

Fährt die ganze Kette für **eine** Idee. Genau **eine** Rückfrage (Gate, Schritt 3), sonst
läuft alles durch — auch eingebundene Skills stellen keine Fragen (siehe Schritt 2 und 4).

**Projekt-Adapter:** Alle projekt­spezifischen Werte (Branches, Testbefehle, Pfade, Reviewer-
Zuständigkeit, Stufen-Kriterien, Vorschau, Harness) stehen in `factory.config.md` des Projekts
(Suche: zuerst `$R/factory.config.md` — außerhalb des Worktrees, damit Implementer `SEALED_ROOT` und `ACCEPTANCE_RUN` nicht lesen —, dann `<repo>/.claude/factory.config.md`). Im Text unten
stehen sie als `{{SLOT}}`. **Fehlt die Datei oder ein Pflicht-Slot, anhalten** und sagen,
welcher fehlt (Vorlage: `factory.config.example.md` neben dieser Datei). Ein leerer
optionaler Slot heißt: der zugehörige Teil entfällt (und das steht im Report).

Shells — auch die der Subagents — starten im Session-Ordner, und `cd` überlebt einen
Aufruf nicht. Deshalb arbeitet der Skill nur mit **absoluten** Pfaden, die im Protokollkopf
stehen (bei `{{PATH_STYLE}} = windows` im Windows-Format per `pwd -W`):

| | Pfad |
|---|---|
| `R` | `{{SESSION_ROOT}}` (Session-Ordner; enthält `M` und den OpenSpec-Ordner) |
| `M` | `$R/{{REPO_DIR}}` — Checkout auf `{{TARGET_BRANCH}}`, ggf. Mount der gemeinsamen Instanz |
| `W` | `{{WORKTREE_PATTERN}}` — Worktree dieses Laufs |
| `S` | `{{OPENSPEC_DIR}}/changes/<slug>` — Spec, Tasks, Protokoll |
| `L` | `{{LOCK_DIR}}` — Sperren und Warteschlange |
| `Z` | `{{SEALED_ROOT}}/<slug>-<zufall>` — **versiegelte Abnahmetests** (siehe „Abnahmetests“) |
| `T` | `{{HARNESS_DIR}}` — optionale Szenario-Harness (echtes Artefakt gegen eine Attrappe) |
| `K` | Ordner dieser `SKILL.md` (für `queue.sh`) |

Git immer mit `git -C "$W"` bzw. `git -C "$M"`. Fehlt der Skill `openspec-propose`, anhalten
und sagen, dass die Session in `R` starten muss (dort liegen die OpenSpec-Skills).

## Harte Regeln

- Nie `{{PROD_BRANCH}}`, nie `{{PROTECTED_JOBS}}`, nie ein MR/PR nach `{{PROD_BRANCH}}` —
  das ist ein eigener Release-Ablauf.
- Push nach `{{TARGET_BRANCH}}` nur, wenn die Tests grün sind, **die versiegelten
  Abnahmetests grün sind** (in Stufen laut `{{ACCEPTANCE_TIERS}}`) **und** in der letzten
  Review-Runde alle zuständigen Reviewer `APPROVED` gemeldet haben.
- Das Gate nie überspringen, auch nicht bei „kleinen“ Ideen.
- **Kein Agent, der Code für den Lauf schreibt oder prüft, kennt die Abnahmetests** — weder
  ihren Ort noch ihren Inhalt (Regeln im Abschnitt „Abnahmetests“). Auch der Hauptagent liest
  sie nicht.
- `{{SECRETS_RULES}}` — keine Secrets lesen oder ausgeben, keine echten Mails/Zahlungen/
  externen Seiteneffekte.
- `M` wird **nie** verändert — dort arbeiten andere Sessions. Einzige Ausnahme: der Pull nach
  dem Push, und nur wenn dort nichts offen ist.
- Die gemeinsame Instanz `{{SHARED_INSTANCE}}` ist **nur zum Ansehen** — für jeden Agenten des
  Laufs: `{{SHARED_INSTANCE_DONTS}}`. Alles, was schreibt oder abmeldet, nur in der eigenen
  Vorschau `:$P` (eigene Kopie der Daten).
- Jeder Stand, den ein Reviewer sehen soll, ist **committet**. Reviewer sehen nur Commits.
- Nur eigene Ressourcen anfassen (Namen mit dem eigenen Slug, eigener Port, eigene Sperre).
  Fremde `factory-*`-Container, Worktrees, Images und Sperren nie löschen, nur nennen.

## Parallelbetrieb

Mehrere `/factory`-Läufe (und andere Sessions) laufen gleichzeitig. Alles Lauf-Eigene trägt
den Slug im Namen; geteilt sind nur das Git-Repo, `origin/{{TARGET_BRANCH}}` und Docker.
Sperren liegen in `$L` (geht an jeden Subagent) und entstehen mit `mkdir` (atomar — scheitert,
wenn es sie schon gibt). **Herzschlag** heißt: wer eine Sperre oder ein Ticket hält oder
darauf wartet, macht jede Minute `touch` darauf — bei langen Befehlen per Hintergrund-Schleife:
`( while sleep 60; do touch "$X" 2>/dev/null || break; done ) & HB=$!` … `kill $HB`.

- **Lauf-Sperre** `$L/run-<slug>/`: verhindert, dass zwei Sessions denselben Lauf fahren.
  Darin `owner` (Startzeit + Zufalls-ID; die ID steht auch im Protokollkopf). Bei jedem Protokolleintrag `touch` auf die Sperre.
  Freigeben in Schritt 8, bei Abbruch und bei „Abbrechen“ am Gate. Ist sie schon da: letzter
  `touch` jünger als 90 min → **anhalten** mit „läuft in einer anderen Session (letztes
  Lebenszeichen vor N min); ist die abgestürzt: `rm -r $L/run-<slug>` und `/factory` erneut“.
  Älter → verwaist, übernehmen (`owner` neu schreiben, ins Protokoll).
- **Push-Sperre** `$L/push/`: hält genau ein Lauf von „rebase“ bis „push“ (Schritt 7),
  damit sich Läufe auf `{{TARGET_BRANCH}}` nicht gegenseitig die Basis wegziehen. Der Halter
  hält den Herzschlag die ganze Zeit (auch während er in der Warteschlange auf die Tests
  wartet). Warten **im Hintergrund** mit `run_in_background`, dann auf die Benachrichtigung
  warten — kein Vordergrund-`sleep`. Letzter `touch` älter als 5 min → verwaist, wird
  weggeräumt:
  `until mkdir "$L/push" 2>/dev/null; do find "$L" -maxdepth 1 -name push -mmin +5 -exec rmdir {} \; ; sleep 15; done`
  Immer freigeben (`rmdir "$L/push"`), auch bei Abbruch.
- **Warteschlange für schwere Jobs** `$L/queue/`: `{{HEAVY_JOBS}}` laufen über alle Läufe
  hinweg **nacheinander, in Ankunftsreihenfolge** — auch die Abnahmetests, wenn
  `{{ACCEPTANCE_RUN}}` schwer ist. Leichte Jobs (`{{TEST_ONE}}`, `{{TEST_LIGHT}}`, Vorschau,
  Screenshots) laufen sofort. Fertig verpackt in `$K/queue.sh`, mit `run_in_background`
  starten: `bash "$K/queue.sh" "$L" <slug>-<job> <ausgabedatei> <befehl …>` — wartet, hält den
  Herzschlag, gibt das Ticket immer zurück, zeigt die letzten Zeilen, Exit-Code = Befehl.
  Die Ausgabedatei liegt unter `$W/.superpowers/` (gitignored). Was das Skript tut —
  auch Subagents halten sich daran:
  ```bash
  Q="$L/queue"; mkdir -p "$Q"; T=$(date +%s%N)-<slug>-<job>; touch "$Q/$T"
  # warten im Hintergrund (run_in_background), bis das eigene Ticket vorne ist; dabei das
  # eigene Ticket frisch halten und Tickets ohne Lebenszeichen seit 5 min (abgestürzt) entfernen
  until touch "$Q/$T"; find "$Q" -type f -mmin +5 -delete; [ "$(ls "$Q" | sort | head -1)" = "$T" ]; do sleep 10; done
  # … Job ausführen, mit Herzschlag auf das Ticket (X="$Q/$T") …
  rm -f "${Q:?}/${T:?}"   # immer, auch wenn der Job scheitert (`:?` — sonst blockt die rm-Sicherheitsprüfung)
  ```
  Die Wartezeit ins Protokoll („wartet auf Warteschlange, Platz N“). Kein Lauf hält ein
  Ticket, während er auf die Push-Sperre wartet — erst Ticket zurückgeben, dann anstellen.
  Ein per TaskStop beendetes `queue.sh` hinterlässt sein Ticket (der Trap greift nicht) →
  eigenes Ticket gezielt löschen.
- **Vorschau-Port**: erster freier aus `{{PREVIEW_PORTS}}`, siehe Schritt 5; steht im Protokoll.
- **Git-Sperren**: alle Worktrees teilen ein `.git`. Meldet git `index.lock`/`unable to lock ref`,
  kurz (Hintergrund-Warten wie oben) warten und den Befehl einmal wiederholen. Nie
  `.git/*.lock` löschen.
- Screenshots: `{{SCREENSHOT_TOOL}}` wählt seinen Debug-Port selbst; Dateinamen tragen den
  Slug. Keinen von allen Sessions geteilten Browser-MCP benutzen.

## Protokoll: `$S/factory-log.md`

Die einzige Wahrheit über den Lauf — Kontext kann zusammengefasst werden, die Datei nicht.
Kopf (einmal, in Schritt 1): Idee, Slug, `R`, `M`, `W`, `S`, `L`, Owner-ID der Lauf-Sperre,
Basis-SHA; nach Schritt 2 `Stufe` + Grund; nach Schritt 3b das **Manifest** der
Abnahmetests (Anzahl + `sha256` je Datei, **kein** Pfad, kein Inhalt); später `P=<Port>`.
Der Pfad `Z` steht **nicht** im Protokoll (Implementer lesen `$S`), nur im Zeiger `{{SEALED_ROOT}}/index/<slug>` (`$L` geht an jeden Subagent, darum dort nicht).
Danach je Ereignis eine Zeile, **sofort** nach dem Ereignis anhängen:

```
| Zeit | Schritt | Runde | Ergebnis | Befund-IDs offen | Commit |
```

Zähler werden aus dieser Datei gelesen, nie aus dem Gedächtnis:
- **Test-Reparatur** (Schritt 5): höchstens 3 Versuche **je Eintritt** in Schritt 5.
- **Abnahme-Reparatur** (Schritt 5, rote Abnahmetests): höchstens 3 Versuche **je Lauf**;
  eine Anforderungs-ID, die nach zwei Fix-Versuchen noch rot ist → Abbruch.
- **Review-Runden** (Schritt 6): höchstens so viele wie die Stufe erlaubt (S: 2, M/L: 5)
  **je Lauf**, auch nach Rücksprung aus Schritt 7. Nach einer Hochstufung gilt die neue Grenze.

## Stufen — wie viel Aufwand der Lauf bekommt

Eine reine Darstellungsänderung braucht keine 40 Minuten Review. Kriterien:
`{{TIER_S}}` / `{{TIER_M}}` / `{{TIER_L}}` (Details `reviewers.md` §3). Der Hauptagent stuft
in Schritt 2 vorab ein; bei M/L entscheidet danach der Abhängigkeits-Prüfer. Der Nutzer sieht
die Stufe am Gate und kann sie dort über „Ändern“ setzen. Stufe und Grund kommen in den
Protokollkopf.

| | **S** — Darstellung/Text | **M** — normal | **L** — kritischer Pfad, Rechte, Daten |
|---|---|---|---|
| Spec | **Kurzplan** vom Hauptagenten, kein OpenSpec, kein Abhängigkeits-Prüfer | Spec-Agent + Abhängigkeits-Prüfer | Spec-Agent + Abhängigkeits-Prüfer |
| Abnahmetests | nur wenn `S` in `{{ACCEPTANCE_TIERS}}` | versiegelt (Schritt 3b) | versiegelt (Schritt 3b), auch Randfälle und Rollen |
| Build | **ein** Implementer für alle Tasks, kein SDD-Task-Review | SDD je Gruppe; Task-Review nur für Gruppen mit Logik (nicht für reine Tests, CSS, CI, Texte) | SDD je Gruppe, jede mit Task-Review |
| Volle Suite | einmal in Schritt 5 | nach Gruppen, die Backend-Code ändern | nach jeder Gruppe |
| Review-Schleife | nur UI/UX (prüft Frontend-Security mit), max. 2 Runden | laut Zuständigkeit, max. 5 | laut Zuständigkeit, max. 5 |
| Modelle | `{{MODELS}}` | | |

Gate, Vorschau, Screenshots, Push-Regeln und Report gelten in jeder Stufe gleich.
**Hochstufen geht automatisch, Herunterstufen nie:** Berührt der echte Diff (Schritt 6.2,
jede Runde) etwas, das die Kriterien einer höheren Stufe erfüllt, gilt ab dieser Runde die
höhere Stufe samt ihren Reviewern — und, falls die neue Stufe versiegelte Abnahmetests
verlangt und es noch keine gibt, wird Schritt 3b nachgeholt (Test-Autor bekommt Spec/Kurzplan,
nicht den Diff). Das kommt ins Protokoll und in den Report. Eine Spec wird dabei nicht
nachgeschrieben, der Kurzplan bleibt.

## Abnahmetests — versiegelt, der bauende Agent kennt sie nicht

Ziel: Der Agent, der die Aufgabe umsetzt, soll gegen die **Anforderungen** bauen, nicht gegen
die Prüfung. Er kennt Spec, Tasks, Testplan-Überschriften und Schnittstellen — die konkreten
Abnahmetests (Eingaben, erwartete Werte, Randfälle) nicht. So kann er sie weder gezielt
erfüllen („teaching to the test“) noch abschwächen, überspringen oder löschen.

**Wer was sieht:**

| Agent | Spec/Tasks | Abnahmetests (Ort + Inhalt) | Ergebnis der Abnahme |
|---|---|---|---|
| Spec-Agent, Abhängigkeits-Prüfer | schreibt/liest | — (gibt es noch nicht) | — |
| **Test-Autor** (Schritt 3b) | liest | **schreibt** | — |
| Hauptagent (Orchestrator) | liest | **nein** — nur Manifest + Runner-Ausgabe | ja |
| Implementer, Fix-Agent | liest | **nein** | nur gefilterte Rückmeldung (siehe unten) |
| Reviewer | liest | **nein** | nur „grün/rot, N/M“ |
| **Abnahme-Richter** (Schritt 5, nur bei Rot) | liest | liest | schreibt die gefilterte Rückmeldung |

**Regeln:**

1. **Ort:** `Z = {{SEALED_ROOT}}/<slug>-<zufall>` (`zufall` = 8 Hex-Zeichen), **außerhalb**
   von `R`, `W` und `S` — eine Repo- oder Spec-Suche findet sie nicht. Der Pfad steht nur in
   im Zeiger `{{SEALED_ROOT}}/index/<slug>` (nicht in `$L` — das bekommt jeder Subagent), nie im Protokoll, nie in `tasks.md`/`design.md`, nie in einem
   Prompt an Implementer, Fix-Agent oder Reviewer.
2. **Hauptagent bleibt blind:** Er liest die Testdateien nie (kein `Read`, kein `cat` auf `Z`),
   bis der Lauf vorbei ist. Sonst sickern sie über seinen Kontext in jeden späteren Prompt —
   und in jeden `fork`. Implementer, Fix-Agenten und Reviewer sind deshalb **immer frische
   Agenten** (`general-purpose`), nie `fork`.
3. **Implementer-Briefing** (in `context.md`): „Es gibt versiegelte Abnahmetests zu dieser
   Spec. Du bekommst sie nicht und sollst sie nicht suchen. Bau gegen die Anforderungen und
   Schnittstellen in der Spec, nicht gegen vermutete Tests. Lies und schreib nur in `W` und
   `S`.“ Eigene Tests (TDD) schreibt der Implementer trotzdem — die gehören ins Repo.
4. **Schnittstellen festlegen:** Damit Test-Autor und Implementer unabhängig voneinander
   arbeiten können, enthält `design.md` (bzw. der Kurzplan) einen Abschnitt
   **„Schnittstellen“**: öffentliche Funktionen/Signaturen, Routen mit Request/Response,
   CLI-Aufrufe, UI-Selektoren/IDs, Fehlercodes. Der Implementer muss sie **genau so** bauen;
   eine Abweichung ist ein Spec-Bruch, kein Stilfrage. Jede Anforderung bekommt eine
   **Anforderungs-ID** (`A1`, `A2`, … in `proposal.md`/Specs).
5. **Ausführen ohne Ablegen:** `{{ACCEPTANCE_RUN}}` lässt die Tests aus `Z` gegen `W` laufen,
   ohne sie in `W` zu kopieren (Read-only-Mount in einen Wegwerf-Container oder Kopie von
   `W` + `Z` in ein Temp-Verzeichnis, das danach gelöscht wird). Die Tests sind damit nie in
   einem Commit, den ein Implementer sieht.
   **Die Ausgabe ist Teil der Versiegelung:** Ein normaler Testlauf druckt bei Rot Quelltext
   und Werte der Tests (Tracebacks, Assertions). `{{ACCEPTANCE_RUN}}` gibt deshalb **nur**
   Zusammenfassung + Namen der roten Tests aus (z. B. pytest `--tb=no -rf`, Rest per `sed`
   abgeschnitten), und die Ausgabedatei liegt in `{{SEALED_ROOT}}/out/<slug>-<n>.txt` — **nie**
   unter `$W` (`$W/.superpowers/` lesen Implementer und Fix-Agenten). Die lange Fassung mit
   Tracebacks erzeugt nur der Abnahme-Richter (Regel 7) selbst, ebenfalls nach
   `{{SEALED_ROOT}}/out/`.
6. **Manipulationsschutz:** Vor jedem Abnahmelauf `sha256sum` über `Z` gegen das Manifest im
   Protokoll — Abweichung = **Abbruch** („Abnahmetests verändert“). Zusätzlich prüft der
   Hauptagent im Diff, ob der Lauf Test-Infrastruktur so ändert, dass fremde Tests anders
   laufen (Test-Konfiguration, globale Fixtures/`conftest`, Skip-/xfail-Marker, Umgebungs­
   erkennung „läuft gerade ein Test?“): jede solche Änderung muss eine Task in `tasks.md`
   begründen, sonst ist sie ein `blocker` für den Security-Reviewer (er bekommt diese Liste).
7. **Gefilterte Rückmeldung bei Rot** (`{{ACCEPTANCE_FEEDBACK}}`): Der Fix-Agent bekommt nie
   den Testcode. Ein frischer **Abnahme-Richter** (liest Tests + Ausgabe, ändert nichts)
   schreibt je rotem Test eine Zeile:
   `A<n> | <Anforderung in eigenen Worten> | erwartet: <Verhalten> | beobachtet: <Verhalten>`
   — bei `requirement` ohne konkrete Testwerte, die nicht schon in der Spec stehen; bei
   `assertion` zusätzlich Testname, Assertion-Text und Traceback-Kopf (nie die Datei).
   Der Richter beurteilt auch, ob der **Test** falsch ist (widerspricht Spec oder
   Schnittstellen) — dann `TESTFEHLER A<n> | Begründung`, und der Hauptagent lässt den
   Test-Autor genau diesen Test korrigieren (neues Manifest ins Protokoll, zählt als
   Reparaturversuch). Ein Test wird nie gelöscht, um grün zu werden.
8. **Nach dem Lauf:** Ist alles grün und die Review-Schleife bestanden, committet der
   Hauptagent die Abnahmetests unter `{{ACCEPTANCE_COMMIT_DIR}}`
   (`test(<slug>): Abnahmetests`) — ab dann sind sie normale Regressionstests. Das passiert
   in Schritt 7 **nach** der letzten Review-Runde und vor dem Rebase; die volle Suite läuft
   danach ohnehin noch einmal. Leerer Slot → nicht committen, `Z` bleibt für spätere Läufe
   liegen (Pfad im Report). **Nach diesem Commit darf kein Fix-Commit
   `{{ACCEPTANCE_COMMIT_DIR}}` berühren** (die Tests sind jetzt normale Dateien im Worktree) —
   der Hauptagent prüft den Diff jedes späteren Fix-Commits, Verstoß = Abbruch.
9. **Ehrliche Grenze:** Die Isolation ist Weglassen + Anweisung + gefilterte Ausgabe +
   Nachkontrolle (Hash, Diff-Prüfung), keine harte Sandbox. Ein Agent mit Shell könnte das Dateisystem
   durchsuchen. Wer es härter will: `Z` auf einem Pfad/Host, auf den die Session keine
   Leserechte hat, und `{{ACCEPTANCE_RUN}}` als Dienst, der nur „bestanden/nicht bestanden“
   zurückgibt. Im Report steht, welche Variante lief.

## Befehle

`W` (und die anderen Pfade außer `Z`) wird **jedem** Subagent wörtlich mitgegeben — ein
`$(pwd)` in einer Subagent-Shell zeigt auf den Session-Ordner, nicht auf den Worktree.
Die **volle** Suite und Artefakt-Builds laufen immer über die Warteschlange
(„Parallelbetrieb“) — auch in Schritt 4 und in Subagents.

- Volle Suite: `{{TEST_FULL}}`
- Nur wenn `{{DEPS_FILES}}` im Diff: `{{TEST_FULL_FRESH_DEPS}}` (Installationsfehler nicht verschlucken)
- Eine Datei (sofort): `{{TEST_ONE}}`
- Leichte Suiten (sofort): `{{TEST_LIGHT}}`
- Abnahme (nur Hauptagent): `{{ACCEPTANCE_RUN}}`

`{{KNOWN_LOCAL_FAILURES}}` nicht als Fehler werten, im Report nennen.

## Schritte

1. **Intake und Preflight.**
   - Slug aus der Idee (kebab-case, ≤ 4 Wörter).
   - Pfade bestimmen (Tabelle oben), `factory.config.md` und `{{PROJECT_RULES}}` lesen (wird
     bei Start außerhalb des Repos nicht automatisch geladen), `mkdir -p "$L"`, dann
     **Lauf-Sperre** nehmen (siehe „Parallelbetrieb“). Gelingt das nicht: anhalten.
   - **Fortsetzen:** Gibt es `$S/factory-log.md`, den Lauf ab dem letzten protokollierten
     Schritt fortsetzen (Gate erneut zeigen, falls es noch nicht beantwortet war; `Z` aus
     dem Zeiger `{{SEALED_ROOT}}/index/<slug>`, fehlt die Datei aber das Manifest steht im Protokoll: Schritt 3b
     neu, neues Manifest). Gibt es Change oder Worktree **ohne** Protokoll: anhalten, nennen
     (Slug ist von Hand oder von einem anderen Werkzeug belegt — anderen Slug vorschlagen).
   - **Selbst starten, nicht anhalten:** Fehlt eine Laufzeit-Voraussetzung (Docker-Daemon,
     lokale Instanz), zuerst `{{AUTOSTART}}` ausführen und im Hintergrund warten, bis sie
     antwortet (ins Protokoll). Erst wenn das scheitert: anhalten und sagen, was fehlt.
   - Preflight, jeder Punkt muss stimmen, sonst anhalten und sagen, was fehlt:
     `{{PREFLIGHT}}`; `git -C "$M" ls-remote origin {{TARGET_BRANCH}}` erreichbar; `openspec`
     und `docker` (falls genutzt) vorhanden; kein eigener alter Container `factory-<slug>-*`
     (sonst entfernen — er gehört zu diesem Slug). Offene Änderungen in `M` und Container
     anderer Läufe sind **kein** Hindernis — nur im Report nennen, dass die
     Vorher-Screenshots den Stand von `M` zeigen.
   - **Externe Voraussetzungen:** Nennt die Idee ein System außerhalb des Repos (URL, Dienst,
     Konto, Token, Server-Konfiguration), jeden Zugang mit `curl -sI` prüfen — erst der
     Statuscode zählt, nicht eine Vermutung. Das Ergebnis kommt als `Voraussetzung:` in den
     Protokollkopf. Ist eine Voraussetzung nicht erfüllt (4xx/5xx, nicht erreichbar, Zugang
     fehlt), wird nicht angehalten. Sie wird aber am Gate die erste Weiche (Schritt 3).
     (Lehre: ein Lauf hat 3 h gegen einen 401 gebaut.)
   - `git -C "$M" fetch origin && git -C "$M" worktree add "$W" -b {{FEATURE_BRANCH}} origin/{{TARGET_BRANCH}}`,
     Protokoll anlegen.

2. **Spec** — in Subagents, damit der Hauptkontext klein bleibt.
   - **Vorab-Einstufung** (Hauptagent, ein paar Greps): Erfüllt die Idee klar `{{TIER_S}}`,
     gibt es keine Spec, sondern einen **Kurzplan**. Im Zweifel nicht S.
     Der Hauptagent schreibt `$S/tasks.md` selbst, ohne OpenSpec und ohne `validate`:
     Ziel (1 Satz), Anforderungen mit IDs, Schnittstellen (falls es welche gibt), Tasks mit
     echten Dateien (vorher Quelltext-Guards in den Tests zur Stelle suchen), Testplan (2–3
     Zeilen, Ansichten in `{{SCREEN_WIDTHS}}`), höchstens 3 Weichen (siehe Gate). Danach
     direkt Schritt 3, der Rest von Schritt 2 entfällt.
   - **Spec-Agent** (`general-purpose`): führt im Ordner `R` den Skill `openspec-propose`
     aus, Change-Name = Slug; bekommt `R`, `M`, `S` und den Pfad `{{PROJECT_RULES}}`.
     Vorgaben im Prompt: **keine Rückfragen** — jede offene Frage wird Annahme mit Default;
     die Schlussempfehlung „/opsx:apply“ ignorieren. Pflichtabschnitte:
     - **Annahmen** in `proposal.md`;
     - **Anforderungen mit IDs** (`A1 …`), jede prüfbar formuliert (Eingabe → Verhalten);
     - **Schnittstellen** in `design.md` (siehe „Abnahmetests“, Regel 4);
     - **Testplan** in `design.md`: Unit-Tests; bei zustandsbehafteten oder dialogartigen
       Abläufen Szenario-Tests über mehrere Schritte; bei Frontend die Ansichten für den
       Browser (`{{SCREEN_WIDTHS}}`); bei `{{REVIEW_RUNTIME}}`-Pfaden die Harness-Szenarien
       (vorhandene aus `$T` nennen, was fehlt als neues Szenario mit Erwartung beschreiben —
       es wird in Schritt 4 in `{{HARNESS_SCENARIO_FILE}}` angelegt, Namen mit Präfix
       `<slug>_`).
     Der Testplan nennt **Testarten und Bereiche**, keine konkreten Abnahme-Testfälle — die
     schreibt der Test-Autor in Schritt 3b versiegelt. Tasks nennen echte Dateien (Code vorher
     mit Grep lesen). `openspec validate <slug>` grün. Die Spec wächst mit der Änderung: eine
     reine Darstellungsänderung bekommt wenige Tasks und einen kurzen Testplan, keinen Roman.
     Rückgabe nur: Ziel (1 Satz), Anforderungs-IDs, Tasks, Testplan, `VORAUSSETZUNGEN` (was
     außerhalb des Codes da sein muss) und **`WEICHEN`**: höchstens 3 Annahmen, bei denen
     eine andere Antwort das sichtbare Ergebnis, die Architektur oder den Aufwand deutlich
     ändert. Je Weiche: Frage, 2–3 Optionen (Default zuerst), bei Optik je Option eine
     ASCII-Skizze (≤ 12 Zeilen). Die übrigen Annahmen stehen nur in `proposal.md`.
   - **Abhängigkeits-Prüfer** (`reviewers.md` §3, Modus „vor dem Build“) danach. Seine
     `TASKS_ADD`/`ANNAHMEN_ADD` trägt der Hauptagent in `tasks.md`/`proposal.md` ein
     (markiert „ergänzt: Abhängigkeiten“), dann `openspec validate <slug>` erneut. Seine
     `STUFE` und `GRUND` kommen in den Protokollkopf. `WEICHEN_ADD` und
     `VORAUSSETZUNGEN_ADD` legt er zu denen des Spec-Agenten. Sind es mehr als 3 Weichen,
     behält er die 3 mit der größten Wirkung, der Rest wird Annahme mit Default.

3. **Gate.** Eine Liste mit 20 Annahmen wird in einer Minute abgenickt, und die echten
   Designfragen kommen dann erst nach dem Push. Darum fragt das Gate die Weichen, statt
   Annahmen aufzuzählen.
   - Kurzfassung im Terminal, höchstens 10 Zeilen:
     - **unerfüllte Voraussetzungen zuerst und fett**,
     - Ziel,
     - Stufe mit Grund und was sie bedeutet (z. B. „S: ein Implementer, nur UI-Review,
       {{TIER_MINUTES}}“), und ob versiegelte Abnahmetests laufen,
     - Task-Gruppen als Überschriften mit Anzahl,
     - „N weitere Annahmen mit Default in `proposal.md`“. Diese nicht aufzählen.
   - Dann **ein** `AskUserQuestion` mit bis zu 4 Fragen:
     - bis zu 3 Weichen (Default als erste Option, „(Recommended)“), bei Optik mit `preview`
       = ASCII-Skizze je Option;
     - zuletzt **Bauen** / **Ändern** / **Abbrechen**.
   - Eine **unerfüllte Voraussetzung** ist immer die erste Weiche:
     - „Erst klären: Lauf anhalten (Recommended)“, wenn der Kern der Idee davon abhängt.
       Das zählt wie Abbrechen.
     - „Trotzdem bauen, nur gegen eine Attrappe getestet“. Das steht dann im Report unter
       „offen“.
   - Antworten ins Protokoll.
   - Weicht eine Weiche vom Default ab und lautet die letzte Antwort „Bauen“: die Antwort per
     `openspec-update-change` (S: direkt in `tasks.md`) einarbeiten und **ohne** erneutes
     Gate bauen.
   - Ändern → Notiz per `openspec-update-change` einarbeiten, Gate erneut. Will der Nutzer
     nur eine andere Stufe, die Stufe im Protokoll ändern (keine Spec-Änderung) und erneut
     fragen. Wird dabei aus S eine höhere Stufe, Schritt 2 ab dem Spec-Agent nachholen.
   - Abbrechen → Worktree, Change und Protokoll bleiben, Lauf-Sperre freigeben, Pfade nennen, Ende.

3b. **Abnahmetests schreiben (versiegelt)** — nur in Stufen laut `{{ACCEPTANCE_TIERS}}`,
   startet direkt nach „Bauen“ und läuft **parallel** zu Schritt 4.
   - `Z` anlegen (`mkdir -p`, Zufallssuffix), Pfad in den Zeiger `{{SEALED_ROOT}}/index/<slug>`.
   - **Test-Autor** (frischer `general-purpose`, nie `fork`; Modell wie Reviewer der Stufe)
     bekommt: `S` (Spec nach dem Gate), `M` (Code-Stand **vor** der Änderung, nur lesen),
     `Z`, `{{ACCEPTANCE_STYLE}}`, `{{ACCEPTANCE_RUN}}`, `{{PROJECT_RULES}}`. **Nicht** `W` —
     der Autor soll gegen die Spec schreiben, nicht gegen den entstehenden Code.
   - Auftrag:
     - je Anforderungs-ID mindestens ein Test, benannt nach der ID (`test_A3_…`), damit
       ein roter Test ohne Quelltext verständlich ist;
     - **zusätzlich Randfälle, die in `tasks.md` nicht aufgezählt sind**: Leer-/Grenzwerte,
       ungültige Eingaben, Rechte/Rollen (`{{SECURITY_ROLES}}`) bei L, Fehlerpfade,
       Wiederholung/Idempotenz, Lang-Text und Escaping bei Kundendaten;
     - nur gegen die Schnittstellen aus `design.md` — keine Annahmen über interne
       Hilfsfunktionen, Dateinamen oder Implementierungsdetails;
     - nichts in `W`, `S` oder `M` schreiben; kein Commit;
     - Tests für **neue** Schnittstellen in eigene Dateien, getrennt von Tests für
       Bestehendes (ein Import einer noch nicht vorhandenen Schnittstelle macht sonst die
       ganze Datei zum Sammelfehler);
     - einmal gegen den **Basis-Stand** (`M`) laufen lassen: die Tests für neues Verhalten
       müssen dort **rot** sein (sonst prüfen sie nichts), Tests für Bestehendes grün.
   - Rückgabe **nur**: Anzahl Tests je Anforderungs-ID, Liste der Randfall-Kategorien,
     Ergebnis gegen Basis (rot/grün je ID), `sha256sum` je Datei. **Kein Testcode, keine
     Testwerte.** Das kommt als Manifest ins Protokoll.
   - Der Hauptagent liest die Dateien in `Z` nicht.

4. **Build.**
   - Zuerst `git -C "$W" fetch origin && git -C "$W" rebase origin/{{TARGET_BRANCH}}`: Spec und
     Gate dauern oft 20+ min, in der Zeit landen fremde Commits (ohne eigene Commits ein
     reiner Fast-Forward). Neue Basis ins Protokoll und in `tasks.md`/`design.md`, falls dort
     ein SHA steht.
   - Skill `superpowers:subagent-driven-development` mit diesen Vorgaben:
     Plan = `$S/tasks.md`; Worktree **existiert schon** (`W`, kein neuer, kein
     `using-git-worktrees`); Abhaken in `$S/` und Docker-Testläufe sind erlaubt und **kein**
     Stoppgrund; Implementer committen je Task (`{{COMMIT_STYLE}}`). **Entfallen:** das
     Final-Review von SDD und `superpowers:finishing-a-development-branch` — das übernehmen
     Schritt 6 und 7.
   - **Stufe S:** kein SDD — ein Implementer bekommt alle Gruppen auf einmal, committet je
     Task, kein Task-Review (das UI-Review in Schritt 6 ist die Prüfung). Weiter mit Schritt 5.
   - **Stufe M/L:** ein Implementer und — laut Stufe — ein Task-Review je Task-Gruppe
     (`## N.` in `tasks.md`), nicht je Einzeltask. SDDs `task-brief` sucht
     „Task N“-Überschriften und findet in OpenSpec-Tasks nichts — den Brief je Gruppe selbst
     schneiden:
     `awk -v n=N '/^## /{in_=($0 ~ "^## " n "[.]")} in_' "$S/tasks.md" > <workspace>/group-N-brief.md`.
     Was alle Subagents brauchen (Pfade außer `Z`, Befehle oben mit eingesetztem `W`,
     Commit-Stil, Pfad zu `{{PROJECT_RULES}}`, „volle Suite nur über `queue.sh`“, **der
     Abnahmetest-Hinweis aus Regel 3**) **einmal** als `<workspace>/context.md` schreiben und
     jedem Prompt nur den Pfad mitgeben. `<workspace>` = Ausgabe von SDDs `sdd-workspace`
     (liegt in `$W/.superpowers/`, gitignored).
   - Volle Suite nach Gruppen laut Stufe (L: jede, M: die Backend-Code ändern, S: keine).
     Ergebnis ins Protokoll.
   - Neue Harness-Szenarien aus dem Testplan legt der Implementer in
     `{{HARNESS_SCENARIO_FILE}}` an (liegt außerhalb des Repos, wird nicht committet); ins
     Protokoll.

5. **Verify** (bei jedem Eintritt neu, 3 Reparaturversuche).
   - Volle Suite (über die Warteschlange) und leichte Suiten. Rot → Ursache beheben
     (`superpowers:systematic-debugging`), committen, neu testen. Nach 3 Versuchen:
     **Abbruch** (siehe unten).
   - **Abnahmetests** (wenn es `Z` gibt; wartet, bis Schritt 3b fertig ist): Manifest prüfen
     (Regel 6), dann `{{ACCEPTANCE_RUN}}` (schwer → über die Warteschlange). Der Hauptagent
     liest nur Exit-Code und Zusammenfassung (bestanden/gesamt, IDs der roten Tests).
     - Grün → ins Protokoll („Abnahme N/N, Manifest ok“).
     - Rot → **Abnahme-Richter** (frischer Agent, Regel 7; bekommt `Z`, lässt die roten Tests
       selbst mit vollem Traceback nach `{{SEALED_ROOT}}/out/` laufen) schreibt die gefilterte
       Rückmeldung nach `$S/acceptance-feedback-<n>.md`; der Hauptagent prüft vor der
       Weitergabe nur, dass darin kein Testcode steht (keine `def test`/`assert`/`expect(`-
       Zeilen). Ein **frischer** Fix-Agent bekommt diese Datei + Spec + `W` (Verhalten zuerst
       als eigener Test im Repo, dann Fix, ein Commit `fix(<bereich>): Abnahme A<n>`).
       Danach Schritt 5 erneut. Zähler „Abnahme-Reparatur“ (Protokoll).
       `TESTFEHLER` → Test-Autor korrigiert genau diesen Test (Regel 7).
   - **Laufzeit-Pfade im Diff** (`{{REVIEW_RUNTIME}}`) **und** seit dem letzten Build
     geändert (SHA im Protokoll): einmal bauen (über die Warteschlange),
     `{{ARTIFACT_BUILD}}`. Beim ersten Mal zusätzlich die **Baseline**:
     `git -C "$M" worktree add "$W-base" <Basis-SHA>`, `{{TEST_FULL_LIST}}` dort, Pass/Fail-Liste
     nach `$S/baseline-tests.txt`.
   - **Szenario-Harness** (nur wenn `{{HARNESS_DIR}}` gesetzt und Laufzeit-Pfade im Diff,
     nach dem Build). `B` = erste 7 Zeichen des Basis-SHA.
     1. Basis-Artefakt `base-$B` nur bauen, wenn es noch nicht existiert (andere Läufe auf
        derselben Basis teilen es), über die Warteschlange: `{{ARTIFACT_BUILD_BASE}}`.
     2. Szenarien = `{{HARNESS_STD_SCENARIOS}}` plus die aus dem Testplan. Je Artefakt
        mindestens 2 Läufe, über die Warteschlange (`{{HARNESS_RUN}}`). Für `base-$B` nur
        Szenarien, für die es noch keine 2 Ergebnisse mit diesem Artefakt gibt.
     3. Vergleich `{{HARNESS_COMPARE}}`, Tabelle und Kurzfassung ins Protokoll.
        - **Nachmessen:** Zwei Läufe trennen Streuung nicht von Rückschritt. Ein gemeldetes
          Szenario läuft deshalb mit dem Lauf-Artefakt auf 6 Läufe auf, erst dann wird
          verglichen.
        - **Rückschritt nach dem Nachmessen zählt wie ein roter Test.**
        - Ebenso rot: ein Testplan-Szenario, das mit dem Lauf-Artefakt nicht 2/2 ok ist.
        - Reparatur wie oben, danach neu bauen und nur das Lauf-Artefakt erneut laufen lassen.
     4. `{{HARNESS_NOTES}}` — fehlt ein Ergebnis, zuerst die Logs der Harness lesen, bevor man
        am Code zweifelt.
   - **`{{PREVIEW_TRIGGER}}` im Diff:** Vorschau-Instanz (einmal starten, Hot-Reload lädt
     Änderungen selbst): `{{PREVIEW_START}}`. `P` = erster freier Port aus
     `{{PREVIEW_PORTS}}` (`curl -s 127.0.0.1:$P` antwortet nicht). Scheitert der Start am
     Port (ein anderer Lauf war schneller), Container entfernen und nächsten Port nehmen.
     `P` ins Protokoll. Ansprechen immer über `http://127.0.0.1:$P` (eigener Cookie-Speicher,
     die gemeinsame Instanz bleibt angemeldet). `curl -sI http://127.0.0.1:$P/` muss antworten.
   - **Testdaten der Vorschau:** `{{PREVIEW_SEED}}` — nur synthetische Daten: Normalfall,
     Leerzustand, Lang-Text mit `<img onerror>`. IDs der Testdaten ins Protokoll — die
     Reviewer brauchen sie. Vorher-Screenshots der gemeinsamen Instanz zeigen echte Daten,
     Nachher synthetische; das im Report sagen.

6. **Review-Schleife** — bis **alle** zuständigen Reviewer `APPROVED` melden.
   Prüflisten, Zuständigkeit, Antwortformat und Befund-IDs: `reviewers.md`.
   1. **Vollständigkeit** (Hauptagent, jede Runde): keine offene `- [ ]` in `tasks.md`, und
      jede Task hat einen Commit, der sie umsetzt. Lücke → zurück zu Schritt 4 nur für diese
      Tasks.
   2. Zuständigkeit aus `git -C "$W" diff --name-only origin/{{TARGET_BRANCH}}...HEAD`
      bestimmen (jede Runde neu), dabei die Stufe gegen den echten Diff prüfen und, wenn
      nötig, hochstufen („Stufen“). Bei S nur der UI/UX-Reviewer.
   3. Zuständige Reviewer **parallel** starten (ein Agent-Aufruf je Reviewer in *einer*
      Nachricht, `general-purpose`, frisch). Jeder bekommt `W`, `L`, `P`, Slug, Spec-Pfad, die
      Befehle oben (ohne `{{ACCEPTANCE_RUN}}`), seine offenen Befunde der Vorrunde (mit IDs),
      seine Prüfliste, den Diff als Datei
      (`git -C "$W" diff origin/{{TARGET_BRANCH}}...HEAD > "$S/review-r<N>.diff"`), das
      Abnahme-Ergebnis als Zahl („Abnahme 14/14 grün“) und — ab Runde 2 — den Commit-Bereich
      der letzten Fix-Runde. Der Security-Reviewer bekommt zusätzlich die Liste geänderter
      Test-Infrastruktur (Regel 6). Die volle Suite läuft beim Hauptagenten parallel zur
      Runde; Reviewer lassen sie nicht noch einmal laufen, sondern bekommen das Ergebnis.
   4. Ergebnis ins Protokoll. Alle `APPROVED` → Schritt 7.
   5. Sonst **ein** frischer Fix-Agent mit allen `blocker`/`major`-Befunden: Verhalten zuerst
      als Test, dann Fix, **ein Commit je Runde** (`fix(<bereich>): Befunde aus Review-Runde N`).
      Widersprechen sich Befunde, gilt `{{CONFLICT_ORDER}}`. Dann Schritt 5 (inkl.
      Abnahmetests), dann nächste Runde.
   6. **Abbruch**, wenn: die Rundengrenze der Stufe erreicht ist, oder eine Befund-ID nach
      einem Fix-Versuch in der nächsten Runde wieder offen ist und auch der zweite
      Fix-Versuch sie nicht schließt, oder ein Fix eine Nutzerentscheidung aus
      `{{PROJECT_RULES}}` umwerfen müsste. `minor`-Befunde blockieren nie, sie kommen in den
      Report.

7. **Ship** — alles von „rebase“ bis „push“ unter der **Push-Sperre**.
   - Abnahmetests übernehmen (Regel 8): nach `{{ACCEPTANCE_COMMIT_DIR}}` kopieren,
     `test(<slug>): Abnahmetests` committen (entfällt bei leerem Slot).
   - `git -C "$W" status --porcelain` leer (sonst committen).
   - Push-Sperre nehmen (im Hintergrund warten, siehe „Parallelbetrieb“), ins Protokoll.
   - `git -C "$W" fetch origin && git -C "$W" rebase origin/{{TARGET_BRANCH}}`. Konflikt →
     `git -C "$W" rebase --abort`, **Abbruch**.
   - Brachte der Rebase fremde Commits, die dieselben Dateien berühren: eine weitere
     Review-Runde (zählt zur Rundengrenze der Stufe).
   - Tests ein letztes Mal grün (Schritt 5 ohne Vorschau-Neustart; die Abnahmetests sind
     jetzt Teil der Suite; die Harness nur, wenn der Rebase Laufzeit-Pfade geändert hat; die
     volle Suite geht auch hier über die Warteschlange, die Push-Sperre bleibt dabei
     gehalten). Brachte der Rebase **nichts** und ist `HEAD` genau der SHA, auf dem die letzte
     Suite laut Protokoll grün war, entfällt der Lauf — ins Protokoll („Tests auf identischem
     SHA grün“). Der Commit der Abnahmetests ändert den SHA; dann läuft die Suite einmal.
   - `git -C "$W" push origin HEAD:{{TARGET_BRANCH}}`. Abgelehnt (jemand außerhalb der Factory
     war schneller): bis zu **zweimal** fetch, rebase, Tests, push. Dann → **Abbruch**.
   - Push-Sperre freigeben (`rmdir "$L/push"`), sofort nach dem Push.
   - `git -C "$M" pull --ff-only` — **nur** wenn `git -C "$M" status --porcelain --untracked-files=no`
     leer ist (ungetrackte lokale Dateien blockieren nicht, der Fast-Forward fasst sie nicht
     an) und der Branch `{{TARGET_BRANCH}}` ist; sonst überspringen und im Report sagen, dass
     die gemeinsame Instanz noch den alten Stand zeigt. Pipeline-Link fürs Protokoll:
     `{{PIPELINE_URL}}`. `{{RELEASE_NOTE}}`
   - **Laufzeit-Pfade im Diff:** Das lokal für Live-Tests genutzte Artefakt ist **nicht** der
     Lauf-Build `factory-<slug>` (Lehre: ein Lauf wurde als fertig gemeldet, und der Live-Test
     lief dann auf einem Stand von morgens).
     - War der Pull in `M` erfolgreich, dort neu bauen, über die Warteschlange:
       `{{ARTIFACT_LOCAL_REFRESH}}`.
     - Wurde der Pull übersprungen, **nicht** bauen (das Artefakt hätte die Änderung nicht).
       Im Report fett: „lokales Artefakt NICHT aktualisiert“.
     - Laufende Instanzen behalten ihr altes Artefakt — gehört in den Report.

8. **Report und Aufräumen.**
   - Aufräumen: `{{CLEANUP}}`, `git -C "$M" worktree remove "$W-base"`, Seed-Daten — jeweils
     nur, wenn vorhanden. `Z` löschen, wenn die Tests committet sind; sonst stehen lassen.
     Zuletzt die Lauf-Sperre freigeben (`rm -r "$L/run-<slug>"`).
   - **Status ehrlich benennen.** Grüne Tests und Reviews belegen nicht, dass es im echten
     Betrieb funktioniert.
     - Berührt der Diff `{{LIVE_STATUS_PATHS}}`, heißt der Status **„gepusht – Live-Test
       offen“**. Nie „fertig“.
     - Dasselbe gilt bei „trotzdem bauen“ trotz unerfüllter Voraussetzung (dann: „gepusht –
       gegen Attrappe getestet“).
     - Dieser Status steht im Protokoll, im Artifact und im ersten Satz der Antwort an den
       Nutzer, zusammen mit der Live-Checkliste.
   - Artifact „Factory: <slug>“ aus dem Protokoll: Status (gepusht / gepusht – Live-Test
     offen / abgebrochen + warum), Idee, Annahmen, Tasks ✓/✗, Testzahlen, **Abnahme**
     (Tests je Anforderungs-ID, Ergebnis gegen Basis und Endstand, Reparaturrunden,
     Isolationsvariante laut Regel 9), Artefakt gebaut?, **Review-Protokoll** (Runden,
     Verdicts, behobene Befunde, offene `minor`), Screenshots vorher/nachher **direkt
     eingebettet** als `data:image/png;base64,…` (bei mehr als 40 Bildern nur die geänderten
     Ansichten), Vorher/Nachher nebeneinander, Commit-SHAs, Pipeline-Link,
     **Harness-Vergleich**, **offene Live-Tests** als Checkliste vom Laufzeit-Reviewer.
     Die Harness ersetzt den Live-Test nicht.
   - Danach `{{POST_RUN_HOOK}}` (falls gesetzt). OpenSpec-Change **nicht** archivieren — das
     passiert nach dem Live-Test per `/opsx:archive` (S-Läufe haben keinen Change, nur
     `tasks.md` und Protokoll). Der Feature-Worktree bleibt stehen.

## Nachtrag nach dem Report

Schaut sich der Nutzer das Ergebnis an und will danach etwas anders („Liste nur mit Datum und
Titel“), ist sein Wunsch die Freigabe — kein neues Gate. Voraussetzung: es bleibt im Rahmen
des Changes. Sonst neuer `/factory`-Lauf.
- Im selben Worktree `W`, vorher `fetch` + `rebase`. Lauf-Sperre wieder nehmen.
- In `tasks.md` einen Abschnitt „Nachtrag (Nutzerwunsch <Datum>)“ mit den Tasks anlegen,
  Zeile ins Protokoll.
- Erst alles suchen, was an der geänderten Stelle hängt (Aufrufer, Quelltext-Guards in den
  Tests), dann ändern; Guards an das neue Verhalten anpassen, nicht löschen. Das gilt auch
  für die committeten Abnahmetests: ändert der Nachtrag eine Anforderung, wird der
  zugehörige Abnahmetest angepasst und das im Commit genannt.
- Fokussierte Tests, Browser-Check in der Vorschau (Seed-Daten neu laden), volle Suite über
  `queue.sh`, ein Commit, Push unter der Push-Sperre, `M` nachziehen, aufräumen.
- Security-Reviewer nur, wenn Backend-Routen oder Rechte im Nachtrag-Diff sind; sonst entfällt
  die Review-Schleife. Report-Artifact nicht neu bauen, Nachtrag in der Antwort nennen.

## Abbruch (aus Schritt 3b–7)

Die Arbeit geht nie verloren: Push-Sperre freigeben, falls gehalten, eigenes
Warteschlangen-Ticket löschen; laufenden Rebase abbrechen (`git -C "$W" rebase --abort`),
offene Änderungen als `wip(factory): <Grund>` committen, wenn `{{ABORT_PUSH_OK}}`: **nur den
Feature-Branch** sichern (`git -C "$W" push origin {{FEATURE_BRANCH}}`), Grund und Schritt ins
Protokoll, dann Schritt 8 mit Status „abgebrochen“. `Z` und der Zeiger
`{{SEALED_ROOT}}/index/<slug>` bleiben stehen, damit ein späterer Lauf dieselben Tests
weiterverwendet. Ein späteres `/factory` mit derselben Idee bzw. demselben
Slug setzt dort fort.

## Stolperfallen (aus echten Läufen)

- `rm -f "$Q/$T"` blockt die rm-Sicherheitsprüfung → `"${Q:?}/${T:?}"` schreiben. Ebenso
  `rm -rf out/...` für alte Harness-Läufe: lieber unter neuem Tag bauen (`factory-<slug>-r1`),
  dann vermischen sich Läufe nicht.
- Python-Werkzeuge unter Windows: Emoji in der Ausgabe stürzen mit cp1252 ab → mit
  `PYTHONIOENCODING=utf-8` starten (in `&&`-Ketten bricht sonst die ganze Kette).
- Git-Bash: jeder Pfad an `docker` braucht `MSYS_NO_PATHCONV=1`, sonst wird `/srv/…` zu
  `C:/Program Files/Git/srv/…`.
- Git-Bash: `$HOME` ist `/c/Users/…`; mit `MSYS_NO_PATHCONV=1` versteht Docker Desktop das
  nicht. `SEALED_ROOT` (und jeden anderen Mount-Pfad) im Windows-Format setzen, z. B.
  `$(cygpath -m "$HOME")/.factory-sealed`.
- `$(pwd)` in einer Subagent-Shell ist der Session-Ordner, nicht der Worktree — Pfade immer
  wörtlich übergeben.
- Der `security-review`-Skill braucht ein Git-Arbeitsverzeichnis; Reviewer arbeiten mit
  `git -C "$W"` oder der Diff-Datei.
- Ein Reviewer, der auf der gemeinsamen Instanz `/logout` aufruft, meldet dort alle ab —
  deshalb „nur ansehen“.
- Lohnt sich die Factory? Bei M/L mit Rechten/Auth/Daten ja (echte Funde: Kontoübernahme,
  Rollen-Lücken, Mobil-Umbruch). Bei kleinen UI-Changes ist S der richtige Modus; bei
  Einzeiler-Bugfixes ist ein normaler Fix schneller.
