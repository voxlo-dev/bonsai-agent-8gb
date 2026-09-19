# T-011 — Verify the server autostart with the real model

- **Summary:** Run `bonsai-pi` with no server up, measure the load time, confirm VRAM is freed after the session
- **Category:** chore
- **Importance:** high
- **Effort:** S
- **Depends on:** none

## Why

`bonsai-pi` starts and stops `bonsai-server` itself (`docs/dev.md#server-lifecycle`). The
lifecycle was verified with a stand-in server only, because the real one was busy at the
time. Unverified with the real model: that llama-server shuts down cleanly on SIGTERM and
releases its VRAM, how long the first session waits for the load, and whether
`SERVER_START_TIMEOUT` 300 fits a cold page cache.

## What

With no server running: `bonsai-pi`, note the time until pi's prompt, check `nvidia-smi`
during the session, exit, check `nvidia-smi` again and that `$BONSAI_HOME/run/` holds no
session or `server.pid`. Repeat with a cold cache (`echo 3 | sudo tee /proc/sys/vm/drop_caches`).
Also Ctrl+C during a generation in pi: the server must survive. Write the load time into
`docs/dev.md#server-lifecycle`.
