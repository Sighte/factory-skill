# /factory — Spec-driven Software Factory for Claude Code

A Claude Code skill that turns **a one-line feature idea** into a complete, reviewed commit
on your integration branch:

## Architecture

### How a run works

```mermaid
flowchart TD
    idea(["/factory &quot;idea&quot;"]) --> intake["1 · Intake & Preflight<br/>Slug, run lock, worktree W,<br/>external requirements via curl"]
    intake --> tier{"Preliminary tier"}
    tier -- "S" --> plan["2 · Short plan<br/>(orchestrator, without OpenSpec)"]
    tier -- "M / L" --> spec["2 · Spec agent<br/>OpenSpec: requirements A1…An,<br/>interfaces, test plan, decision points"]
    spec --> deps["Dependency checker<br/>add tasks, set tier"]
    plan --> gate
    deps --> gate{{"3 · APPROVAL GATE – the only question<br/>≤ 3 decision points + Build / Change / Abort"}}
    gate -- "Change" --> spec
    gate -- "Abort" --> stop(["End, work is left in place"])
    gate -- "Build" --> author & build

    author["3b · Test author<br/>writes sealed acceptance tests<br/>only from spec + old code"]:::sealed --> Z[("Z · sealed<br/>outside repo & spec<br/>+ sha256 manifest")]:::sealed
    build["4 · Build<br/>implementer per task group (SDD),<br/>own TDD tests, commits in W"] --> verify

    Z -.->|result only| verify
    verify["5 · Verify<br/>full suite · acceptance tests · artifact build<br/>scenario harness · preview instance"]
    verify -- "red" --> judge["Acceptance judge<br/>translates into: A3 expected X, observed Y"]:::sealed
    judge --> fixA["Fix agent (fresh)<br/>sees only the feedback"] --> verify
    verify -- "green" --> review

    review["6 · Review loop (parallel)<br/>Security · Runtime · Dependencies · UI/UX"]
    review -- "CHANGES_REQUESTED<br/>(max. 2 or 5 rounds)" --> fixR["Fix agent<br/>one commit per round"] --> verify
    review -- "all APPROVED" --> ship

    ship["7 · Ship (under push lock)<br/>commit acceptance tests → rebase →<br/>tests → push TARGET_BRANCH"] --> report
    report(["8 · Report artifact + cleanup<br/>Honest status: “pushed – live test pending”"])

    classDef sealed fill:#fde7e7,stroke:#c0392b,color:#000
```

Aborting is possible from any step from 3b onward (limits for repairs and rounds are in the
log): work is committed as `wip`, the feature branch is saved, and a later invocation
with the same slug resumes.

### Who sees the acceptance tests?

```mermaid
flowchart LR
    subgraph sichtbar["sees code & spec – not the acceptance tests"]
        impl["Implementer"]
        fix["Fix agents"]
        rev["Reviewers"]
        main["Main agent<br/>(orchestrator)"]
    end
    subgraph versiegelt["sealed"]
        author["Test author"]:::sealed
        Z[("Z · acceptance tests")]:::sealed
        judge["Acceptance judge"]:::sealed
    end
    W[("Worktree W<br/>+ spec S")]

    impl & fix -- "read/write" --> W
    rev -- "read" --> W
    author -- "writes" --> Z
    judge -- "reads" --> Z
    Z -- "only: passed N/M,<br/>red test IDs" --> main
    judge -- "filtered feedback<br/>(requirement, no test code)" --> fix
    main -- "result as a number" --> rev

    classDef sealed fill:#fde7e7,stroke:#c0392b,color:#000
```

### Parallel runs

```mermaid
flowchart LR
    r1["Run A"] & r2["Run B"] & r3["Run C"] --> L
    subgraph L["L · Lock folder"]
        run["run-&lt;slug&gt;/<br/>one run per slug"]
        q["queue/<br/>FIFO for heavy jobs<br/>(full suite, builds, harness)"]
        push["push/<br/>exactly one run from rebase to push"]
    end
    push --> origin[("origin/TARGET_BRANCH")]
```

All locks use `mkdir` (atomic) and a heartbeat via `touch`; orphaned locks are cleaned up by
the next run.

Origin: developed and refined in the MeetingAgent project over ~10 real runs; this is
the project-neutral version. Everything project-specific lives in **one** file,
`factory.config.md`.

## What makes it different

- **Exactly one approval gate.** Instead of nodding through 20 assumptions, the gate asks at most 3 "decision points" —
  decisions that significantly change the result, architecture or effort — with
  ASCII sketches for visual matters. After that, everything runs through without further questions.
- **Sealed acceptance tests.** A dedicated test author writes acceptance tests from the spec into
  a folder outside the repo and the spec. **The agent implementing the task does not know
  them** — neither location nor content — and so can neither tailor its work to them nor weaken them.
  The orchestrator and reviewers also see only the result. On red, the fix agent gets only
  filtered feedback ("Requirement A3: expected X, observed Y"), never the test code.
  Hash manifest against tampering; changes to test infrastructure are a security finding.
  Once acceptance passes, the tests are committed as regression tests.
  Details: `SKILL.md`, section "Acceptance tests" (including an honest limit of the isolation).
- **Tiers S/M/L.** A CSS change does not get a 40-minute review. The tier is estimated
  up front, shown at the approval gate, and automatically raised based on the real diff, never lowered.
- **Review loop until everyone is satisfied** — with finding IDs, round limits, clear
  abort rules and a conflict order.
- **Parallel runs.** Several runs in several sessions at once: run lock,
  push lock, FIFO queue for heavy jobs (`queue.sh`) with heartbeat.
- **Honest status.** Green tests ≠ works live: for critical paths the status is
  "pushed – live test pending", with a checklist.
- **Resumable.** `$S/factory-log.md` is the single source of truth; invoking again with
  the same slug resumes.

## Files

| File | Content |
|---|---|
| `SKILL.md` | The procedure (steps 1–8, acceptance tests, parallel runs, abort, follow-up) |
| `reviewers.md` | Checklists, responsibilities and response format of the reviewers |
| `queue.sh` | Queue for heavy jobs (generic, usable unchanged) |
| `factory.config.example.md` | Template for the project adapter — all slots |
| `examples/meetingagent.factory.config.md` | Filled-in example from the original project (contains internal names/URLs — remove before publishing the repo) |

## Requirements

Required:
- Claude Code with subagents (`Agent` tool) and `AskUserQuestion`.
- [OpenSpec](https://github.com/Fission-AI/OpenSpec) CLI (`openspec`) and the OpenSpec skills
  in the session folder (`openspec init` creates `openspec-propose`, `openspec-update-change`,
  `opsx:archive` …).
- Superpowers plugin: `superpowers:subagent-driven-development`,
  `superpowers:systematic-debugging`.
- Skill `security-review` (built into Claude Code).
- `git` with worktrees, `bash` (Git Bash on Windows), `curl`.

Optional:
- Docker (test runs in containers, preview instance, artifact builds).
- UI skills for the UI/UX reviewer: `taste-skill`, `ui-ux-pro-max`, `design:*`.
- A headless screenshot tool that can run in parallel (e.g. a small
  Puppeteer/CDP script).
- A scenario harness/simulator for end-to-end tests of the shipped artifact.

## Installing in a project

1. Put the skill folder into the project (or globally):
   ```bash
   git clone git@github.com:Sighte/factory-skill.git <repo>/.claude/skills/factory
   # or as a submodule, so updates come along
   ```
   If the session starts not in the repo but in a parent folder (worktrees as
   siblings), create `.claude/skills/factory` there as a link to the repo folder.
2. Copy `factory.config.example.md` to `$R/factory.config.md` (session folder,
   **outside** the repo — the config names the location and runner of the sealed tests, and
   implementers read the worktree) and fill in **every** slot. Fastest: ask Claude in a session "to fill in the factory.config.md for
   this repo based on the template" — and check the result yourself (branches,
   protected jobs, test commands).
3. Add to the project rules (`CLAUDE.md`):
   > Exception `/factory`: after the approval gate, green tests, passed acceptance and
   > review loop, pushes directly to `<TARGET_BRANCH>`, without an MR.

   Otherwise the reviewers report this as a finding.
4. Add `.superpowers/` to `.gitignore` (working folder of the subagents).
5. Do a first run with a small idea (tier S) and read `factory-log.md`.

## Usage

```
/factory "News button in the header, shows the last 5 changes"
```

At the approval gate: answer the decision points, then **Build** / **Change** / **Abort**. After that the
run proceeds on its own until the push and ends with a report artifact (status, acceptance per
requirement, review log, before/after screenshots, pending live tests).

## Customizing

- More/different reviewers: section in `reviewers.md` + row in the responsibilities table +
  slot in the config.
- Stricter acceptance isolation: `SKILL.md`, acceptance tests rule 9 (separate host/service for `Z`).
- Project lessons belong in the config (`*_EXTRA`, `HARNESS_NOTES`), not in `SKILL.md` —
  that way the skill stays the same across projects.
