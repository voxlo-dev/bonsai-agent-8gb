# Plan: {Project Name}

Generated: {date}
Task: {one-line task summary}

## Target & Systems

- **Goal:** {what this builds, for whom}
- **Main systems / components:** {the parts involved}
- **Non-goals:** {explicitly out of scope}

## Features

- {feature 1}
- {feature 2}

## Stack

Binding for `localagent-scaffold`; decided with the user, not by an agent mid-run.

- **Language / runtime:** {and version}
- **Package manager:** {}
- **Test runner:** {and the command that runs it}
- **Key libraries:** {only what the features actually need — or "none"}
- **Already set up?** {what the repo already has, or "empty repo — scaffold from scratch"}

## Test Strategy

- **Levels that matter here:** {unit / integration / e2e — and why}
- **e2e surface?** {browser/UI · HTTP API · CLI · "none"}; settled here, binding for the harness
  `localagent-scaffold` installs and for whether e2e runs at all in finalize. A UI is a surface. A
  process with a real boundary is a surface: an API driven over HTTP, **a CLI driven as a
  subprocess against real files**. A library nothing runs is not
- **Existing tests to build on:** {paths, or "none"}

## Units

Small, independently implementable + testable — each bounds every later agent's context and costs one
spec/implement/review cycle.

**Fewer than feels natural.** A unit is something that can fail its own test, not a layer, a folder
or a file. Splitting by architecture (types · server · client · state) multiplies specs and
interfaces without adding coverage, and three dispatches per unit is what the run is paying for. A
small project is 2–4 units; reach for more only when the features genuinely are.

| ID | Title | Scope (one line) | Depends on |
| --- | --- | --- | --- |
| U1 | {title} | {what it does} | — |
| U2 | {title} | {what it does} | U1 |

## Open Questions

- {anything that needs a human decision before building — or "none"}
