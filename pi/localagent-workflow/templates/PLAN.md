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
- **Test runner:** {name, version, and the exact command that runs it — the scaffold installs exactly this and guesses nothing}
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

One unit is **one worker dispatch, and a dispatch is cut off after a fixed number of turns**. So a
unit is what one agent can spec, test and build in a dozen turns: **one file, three to five
acceptance criteria.** A relay server with a lobby, a tick loop and reconnect handling is three
units, not one; a rules engine with movement, collision and scoring is two. More units cost one
dispatch each and nothing else; a unit too big costs the dispatch and comes back with nothing.

Cut by behaviour that can fail its own test, not by architecture: "room codes and join
validation", not "types". Order them so each builds on finished ones.

| ID | Title | Scope (one line) | Depends on |
| --- | --- | --- | --- |
| U1 | {title} | {what it does} | — |
| U2 | {title} | {what it does} | U1 |

## Open Questions

- {anything that needs a human decision before building — or "none"}
