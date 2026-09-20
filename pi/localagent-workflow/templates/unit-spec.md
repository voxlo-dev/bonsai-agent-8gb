# Spec: U{N} — {Title}

> The unit's whole contract: interface, behaviour, acceptance. The implementer builds from this file
> and the reviewer writes one test per criterion from it. **~80 lines at most** — it is read twice.

## Interface

What this unit exposes, in prose — one line per symbol: where it lives, what it takes, what it
returns, what it raises.

- `{path}`: `{name}({args})` → {what comes back}; raises {when}

How it is reached from outside — the command, the route, the entry point — or "none but the symbols
above":

- `{METHOD} {route}` → {request} ⇒ {response}  ·  `{cli command}` → {what it prints / its exit code}

## Scope

- {exactly what this unit creates or changes}

## Out of Scope

- {what this unit must not touch — behaviour owned by another unit}

## Behaviour

- {observable behaviour, concrete enough to implement against}
- {error / edge cases and their expected handling}

## Acceptance

1. {observable condition that must hold — the reviewer writes one test per line here}
2. ...

## Consumes from prior units

- {interface line this builds on — copy from STATE Interfaces} — or "none"

## Key Files

- {path}: {create | modify — what}
