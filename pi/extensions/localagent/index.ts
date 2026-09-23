// Runs the localagent workflow (./workflow, copied from pi/localagent-workflow) on pi.
// `pi --localagent` makes the session its orchestrator: the workflow skill is offered, the
// orchestrator prompt appended to the system prompt (with a line saying whether a human is
// reachable, so the plan gate is not the model's guess), and the `dispatch` tool starts one
// localagent-* agent as a separate `pi -p` process, one at a time. Without the flag it does nothing.
// Two limits come from the environment, set by bin/bonsai-pi from config.env: LOCALAGENT_AGENT_MODEL,
// the models.json entry the agents run on (a smaller thinking budget than the orchestrator), and
// LOCALAGENT_MAX_TURNS, a backstop after which a runaway dispatch is killed and reported as BLOCKED. After a DONE the
// tool runs the unit's test command itself, so the gate is a fact in the result, not a model turn.
// Rationale: docs/localagent.md.
import { spawn, spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { StringEnum } from "@earendil-works/pi-ai";
import { type ExtensionAPI, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const here = path.dirname(fileURLToPath(import.meta.url));
const workflow = path.join(here, "workflow");
const STATUS = /^(DONE|ESCALATE|BLOCKED|PASS|FIXES_REQUIRED|NO_SURFACE)\b/;
const MAX_TURNS = Math.max(1, Number(process.env.LOCALAGENT_MAX_TURNS) || 30);
const AGENT_MODEL = process.env.LOCALAGENT_AGENT_MODEL || "";

interface Agent {
	name: string;
	primary: boolean;
	prompt: string;
}

function loadAgents(): Agent[] {
	const dir = path.join(workflow, "agents");
	return fs
		.readdirSync(dir)
		.filter((f) => f.endsWith(".md"))
		.sort()
		.map((f) => {
			const { frontmatter: fm, body } = parseFrontmatter<Record<string, any>>(fs.readFileSync(path.join(dir, f), "utf8"));
			return {
				name: fm.name ?? f.slice(0, -3),
				primary: fm.mode === "primary",
				prompt: body,
			};
		});
}

// pi's own entry point, so a child runs the same pinned version (as in pi's subagent example).
function piInvocation(args: string[]): [string, string[]] {
	const script = process.argv[1];
	if (script && fs.existsSync(script)) return [process.execPath, [script, ...args]];
	return ["pi", args];
}

function lastText(message: any): string {
	const parts = Array.isArray(message?.content) ? message.content : [];
	return parts
		.filter((p: any) => p.type === "text")
		.map((p: any) => p.text)
		.join("\n")
		.trim();
}

// The orchestrator gets the agent's status line; a model that talks on gets its last line.
function statusLine(text: string): string {
	const lines = text.split("\n").map((l) => l.replace(/^[`*\s]+|[`*\s]+$/g, "")).filter(Boolean);
	return [...lines].reverse().find((l) => STATUS.test(l)) ?? lines.at(-1) ?? "";
}

export default function (pi: ExtensionAPI) {
	pi.registerFlag("localagent", {
		description: "Run this session as the localagent-workflow orchestrator",
		type: "boolean",
		default: false,
	});

	let agents: Agent[] = [];
	let queue: Promise<unknown> = Promise.resolve();

	pi.on("session_start", async (_event, ctx) => {
		if (!pi.getFlag("localagent")) return;
		agents = loadAgents();
		const subagents = agents.filter((a) => !a.primary).map((a) => a.name);
		if (!agents.some((a) => a.primary) || !subagents.length) {
			ctx.ui.notify(`localagent: no orchestrator or no agents in ${workflow}/agents`, "error");
			return;
		}

		ctx.ui.notify(
			`localagent is experimental: one small feature has run end to end, large tasks have not. ` +
				`Agents: ${AGENT_MODEL || "the session model"}, at most ${MAX_TURNS} turns each. See docs/localagent.md#status.`,
			"warning",
		);

		pi.registerTool({
			name: "dispatch",
			label: "Dispatch",
			description:
				"Run one localagent-* agent on a brief and wait for its one-line result (DONE, ESCALATE, BLOCKED, ...). " +
				"The agent starts with an empty context: the brief must carry the absolute working directory, the " +
				"commands, the task, and the paths of its inputs. Agents run one at a time; a runaway is cut off " +
				`after ${MAX_TURNS} turns (BLOCKED). With \`test\`, the command runs after a DONE and its verdict is appended ` +
				"to the result together with the files the agent changed.",
			promptSnippet: "Run one localagent-* agent on a brief and return its status line",
			parameters: Type.Object({
				agent: StringEnum(subagents as [string, ...string[]], { description: "Agent name" }),
				brief: Type.String({ description: "Working directory, commands, task, input paths" }),
				test: Type.Optional(Type.String({ description: "Test command to run in the working directory after a DONE" })),
			}),
			async execute(_id, params, signal, onUpdate, ctx) {
				const run = queue.then(() => dispatch(params.agent, params.brief, params.test, signal, onUpdate, ctx));
				queue = run.catch(() => {});
				return run;
			},
		});
	});

	pi.on("resources_discover", async () => {
		if (pi.getFlag("localagent")) return { skillPaths: [workflow] };
	});

	// The plan gate needs to know whether anyone can answer it; pi knows, the model does not.
	pi.on("before_agent_start", async (event, ctx) => {
		const orchestrator = agents.find((a) => a.primary);
		if (!orchestrator) return;
		const gate = ctx.hasUI
			? "A human is at this session: the plan gate is binding. Show the plan and stop until it is approved."
			: "No human is reachable (headless): record the plan gate as auto-approved in STATE.md and continue.";
		return { systemPrompt: `${event.systemPrompt}\n\n${orchestrator.prompt}\n\n## Session\n\n${gate}` };
	});

	async function dispatch(name: string, brief: string, test: string | undefined, signal: AbortSignal | undefined, onUpdate: any, ctx: any) {
		const agent = agents.find((a) => a.name === name && !a.primary);
		if (!agent) throw new Error(`BLOCKED unknown agent ${name}`);

		// Nothing the orchestrator session loaded reaches the child: no extensions (so no nested
		// dispatch), no skills, no AGENTS.md. The brief is its whole context.
		const args = ["--mode", "json", "-p", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files"];
		if (AGENT_MODEL) args.push("--model", AGENT_MODEL);
		const sessionFile = ctx.sessionManager.getSessionFile();
		const sessionDir = sessionFile ? path.join(path.dirname(sessionFile), "dispatch", ctx.sessionManager.getSessionId()) : "";
		if (sessionDir) args.push("--session-dir", sessionDir);
		else args.push("--no-session");
		args.push("--append-system-prompt", agent.prompt, "--", brief);

		let turns = 0;
		let final: any;
		let stderr = "";
		let cutOff = false;
		// What the agent is doing, as far as its event stream shows it: the orchestrator only ever
		// gets the status line back, so this is the one live view of a dispatch. The full one is
		// the child's session JSONL - see runs/watch-dispatch.py.
		let usage = "";
		let said = "";
		const trim = (s: string, n: number) => (s.length > n ? `${s.slice(0, n)}…` : s);
		const progress = (what: string) =>
			onUpdate?.({
				content: [{ type: "text", text: [`${name} · turn ${turns}${usage} · ${what}`, said].filter(Boolean).join("\n") }],
				details: {},
			});

		const code = await new Promise<number>((resolve) => {
			const [cmd, argv] = piInvocation(args);
			const proc = spawn(cmd, argv, { cwd: ctx.cwd, stdio: ["ignore", "pipe", "pipe"] });
			let buffer = "";
			const onLine = (line: string) => {
				let event: any;
				try {
					event = JSON.parse(line);
				} catch {
					return;
				}
				if (event.type === "tool_execution_start") {
					const a = event.args ?? {};
					progress(`${event.toolName} ${trim(String(a.path ?? a.command ?? JSON.stringify(a)).replace(/\s+/g, " "), 300)}`);
				} else if (event.type === "message_end" && event.message?.role === "assistant") {
					turns++;
					final = event.message;
					const u = event.message.usage ?? {};
					usage = u.totalTokens ? ` · ${u.output ?? 0} out · ${u.totalTokens} ctx` : "";
					// Its own words beat "thinking": the last line of whatever it just said or thought.
					const parts = Array.isArray(event.message.content) ? event.message.content : [];
					const spoke = parts
						.map((p: any) => (p.type === "text" ? p.text : p.type === "thinking" ? p.thinking : ""))
						.filter(Boolean)
						.join("\n")
						.trim();
					said = spoke ? trim(spoke.split("\n").filter(Boolean).at(-1) ?? "", 300) : "";
					progress("thinking");
					// A backstop, not a rule: no agent has ever stopped itself, and none is told the number.
					if (turns >= MAX_TURNS && final.stopReason !== "stop") {
						cutOff = true;
						kill();
					}
				}
			};
			proc.stdout.on("data", (d) => {
				buffer += d.toString();
				const lines = buffer.split("\n");
				buffer = lines.pop() ?? "";
				lines.forEach(onLine);
			});
			proc.stderr.on("data", (d) => (stderr += d.toString()));
			proc.on("close", (c) => {
				if (buffer.trim()) onLine(buffer);
				resolve(c ?? 1);
			});
			proc.on("error", (e) => {
				stderr += String(e);
				resolve(1);
			});
			const kill = () => {
				proc.kill("SIGTERM");
				setTimeout(() => proc.exitCode === null && proc.kill("SIGKILL"), 5000).unref();
			};
			if (signal?.aborted) kill();
			else signal?.addEventListener("abort", kill, { once: true });
		});

		if (signal?.aborted) throw new Error(`BLOCKED ${name} aborted`);
		if (cutOff) {
			throw new Error(
				`BLOCKED ${name} ran ${MAX_TURNS} turns without returning. Log: ${sessionDir || "(no session)"}`,
			);
		}
		const stop = final?.stopReason;
		if (code !== 0 || !final || (stop && stop !== "stop")) {
			const why = final?.errorMessage ?? (stop && stop !== "stop" ? `stopped on ${stop}` : stderr.trim().slice(-500) || `exit ${code}`);
			throw new Error(`BLOCKED ${name} did not finish: ${why}`);
		}
		let line = statusLine(lastText(final)) || `BLOCKED ${name} returned no status line`;
		if (/^DONE\b/.test(line)) line += gate(ctx.cwd, test);
		return { content: [{ type: "text", text: line }], details: { turns } };
	}

	// The objective gate after a DONE: the test command's verdict and the files the agent changed.
	// Both are facts the orchestrator used to spend eight turns establishing.
	function gate(cwd: string, test: string | undefined): string {
		let out = "";
		if (test) {
			const r = spawnSync("bash", ["-lc", test], { cwd, encoding: "utf8", timeout: 300_000 });
			const tail = `${r.stdout ?? ""}${r.stderr ?? ""}`.trim().split("\n").slice(-3).join(" | ").slice(0, 300);
			out += r.status === 0 ? " · tests: green" : ` · tests: RED (exit ${r.status ?? "timeout"}): ${tail}`;
		}
		const g = spawnSync("git", ["status", "--porcelain"], { cwd, encoding: "utf8" });
		if (g.status === 0) {
			const files = g.stdout.split("\n").filter(Boolean).map((l) => l.slice(3));
			out += ` · changed: ${files.length ? files.slice(0, 20).join(" ") : "nothing"}${files.length > 20 ? " …" : ""}`;
		}
		return out;
	}
}
