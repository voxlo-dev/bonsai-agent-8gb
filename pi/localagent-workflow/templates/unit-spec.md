# Spec: U{N} — {Title}

> Written by the unit's worker before its tests and its code. What it says is the contract; how
> long it is does not matter and is not checked.

## Interface

One line per symbol: where it lives, what it takes, what it returns, what it raises.

- `{path}`: `{name}({args})` → {what comes back}; raises {when}

How it is reached from outside — the command, the route, the entry point — or "none but the symbols
above":

- `{cli command}` → {what it prints / its exit code}  ·  `{METHOD} {route}` → {request} ⇒ {response}

## Behaviour

- {observable behaviour, concrete enough to build against; the details the plan left open, decided}
- {error / edge cases and their expected handling}

## Out of scope

- {what this unit must not touch — behaviour another unit owns}

## Acceptance

Three to five. Each becomes one test, named after it.

1. {observable condition that must hold}
2. ...

## Builds on

- {interface line from the brief} — or "none"
