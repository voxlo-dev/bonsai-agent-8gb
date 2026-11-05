#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# The tool-call round-trip behind `las check`, against a running OpenAI-compatible server (stdlib
# only): a request with one tool must come back with a well-formed tool_calls entry, and sending
# the tool's result back must produce a final answer. Exits 0 when both hold, else 1 naming the
# failing step: request, tool_calls, arguments, result or answer. A failure in tool_calls or
# arguments usually means the GGUF's own chat template does not render or parse tool calls;
# CHAT_TEMPLATE in the model file replaces it (docs/dev.md).
# Needs: the server up. SERVER_URL and MODEL_ALIAS from the environment, --url and --model win.
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

TOOL = {
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Current weather of a city.",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string", "description": "City name"}},
            "required": ["city"],
        },
    },
}


class Fail(Exception):
    def __init__(self, step, why):
        super().__init__(why)
        self.step = step


def chat(url, model, messages, timeout):
    body = {"model": model, "messages": messages, "tools": [TOOL], "tool_choice": "auto",
            "max_tokens": 4096, "temperature": 0}
    req = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            msg = json.load(r)["choices"][0]["message"]
    except urllib.error.HTTPError as e:
        raise Fail("request", f"HTTP {e.code}: {e.read()[:300].decode(errors='replace')}")
    except (OSError, ValueError, KeyError, IndexError) as e:
        raise Fail("request", f"{type(e).__name__}: {e}")
    return msg


def check(url, model, timeout):
    messages = [{"role": "user", "content": "What is the weather in Paris right now? Use the tool."}]
    msg = chat(url, model, messages, timeout)
    calls = msg.get("tool_calls") or []
    if not calls:
        raise Fail("tool_calls", f"no tool_calls in the reply (content: {(msg.get('content') or '')[:200]!r})")
    call = calls[0]
    fn = call.get("function") or {}
    if fn.get("name") != TOOL["function"]["name"] or not call.get("id"):
        raise Fail("tool_calls", f"malformed entry: {json.dumps(call)[:300]}")
    try:
        args = json.loads(fn.get("arguments") or "")
    except ValueError:
        raise Fail("arguments", f"not JSON: {fn.get('arguments')!r}")
    if not isinstance(args, dict) or not isinstance(args.get("city"), str):
        raise Fail("arguments", f"lack the required string 'city': {args!r}")

    messages.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": calls})
    messages.append({"role": "tool", "tool_call_id": call["id"],
                     "content": json.dumps({"city": args["city"], "temperature_c": 18, "sky": "cloudy"})})
    try:
        msg = chat(url, model, messages, timeout)
    except Fail as e:
        raise Fail("result", e.args[0])
    if not (msg.get("content") or "").strip():
        raise Fail("answer", "no final answer after the tool result" + (
            " (it called the tool again)" if msg.get("tool_calls") else ""))
    return msg["content"].strip()


def main():
    ap = argparse.ArgumentParser(description="Tool-call round-trip against an OpenAI-compatible server.")
    ap.add_argument("--url", default=os.environ.get("SERVER_URL", "http://127.0.0.1:8080"))
    ap.add_argument("--model", default=os.environ.get("MODEL_ALIAS", ""))
    ap.add_argument("--timeout", type=float, default=300)
    a = ap.parse_args()
    try:
        answer = check(a.url, a.model, a.timeout)
    except Fail as e:
        print(f"xx tool check failed at step '{e.step}': {e}", file=sys.stderr)
        return 1
    print(f"ok tool check passed against {a.url}: {answer[:120]!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
