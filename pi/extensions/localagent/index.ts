// Runs the localagent workflow (./workflow, copied from pi/localagent-workflow) on pi.
// `pi --localagent` makes the session its orchestrator: the workflow skill is offered, the
// orchestrator prompt appended to the system prompt (with a line saying whether a human is
// reachable, so the plan gate is not the model's guess), and the `dispatch` tool starts one
// localagent-* agent as a separate `pi -p` process, one at a time. Without the flag it does nothing.
// Rationale: docs/dev.md#localagent-workflow.
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { StringEnum } from "@earendil-works/pi-ai";
import { type ExtensionAPI, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const here = path.dirname(fileURLToPath(import.meta.url));
const workflow = path.join(here, "workflow");
const STATUS = /^(DONE|ESCALATE|BLOCKED|PASS|FIXES_REQUIRED|NO_SURFACE)\b/;

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

		pi.registerTool({
			name: "dispatch",
			label: "Dispatch",
			description:
				"Run one localagent-* agent on a brief and wait for its one-line result (DONE, ESCALATE, BLOCKED, ...). " +
				"The agent starts with an empty context: the brief must carry the absolute working directory, the standing " +
				"constraints, the task, and the paths of its inputs. Agents run one at a time.",
			promptSnippet: "Run one localagent-* agent on a brief and return its status line",
			parameters: Type.Object({
				agent: StringEnum(subagents as [string, ...string[]], { description: "Agent name" }),
				brief: Type.String({ description: "Working directory, constraints, task, input paths" }),
			}),
			async execute(_id, params, signal, onUpdate, ctx) {
				const run = queue.then(() => dispatch(params.agent, params.brief, signal, onUpdate, ctx));
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

	async function dispatch(name: string, brief: string, signal: AbortSignal | undefined, onUpdate: any, ctx: any) {
		const agent = agents.find((a) => a.name === name && !a.primary);
		if (!agent) throw new Error(`BLOCKED unknown agent ${name}`);

		// Nothing the orchestrator session loaded reaches the child: no extensions (so no nested
		// dispatch), no skills, no AGENTS.md. The brief is its whole context.
		const args = ["--mode", "json", "-p", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files"];
		const sessionFile = ctx.sessionManager.getSessionFile();
		if (sessionFile) args.push("--session-dir", path.join(path.dirname(sessionFile), "dispatch", ctx.sessionManager.getSessionId()));
		else args.push("--no-session");
		args.push("--append-system-prompt", agent.prompt, "--", brief);

		let turns = 0;
		let final: any;
		let stderr = "";
		const progress = (what: string) =>
			onUpdate?.({ content: [{ type: "text", text: `${name} · turn ${turns} · ${what}` }], details: {} });

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
					progress(`${event.toolName} ${String(a.path ?? a.command ?? "").slice(0, 80)}`);
				} else if (event.type === "message_end" && event.message?.role === "assistant") {
					turns++;
					final = event.message;
					progress("thinking");
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
		const stop = final?.stopReason;
		if (code !== 0 || !final || (stop && stop !== "stop")) {
			const why = final?.errorMessage ?? (stop && stop !== "stop" ? `stopped on ${stop}` : stderr.trim().slice(-500) || `exit ${code}`);
			throw new Error(`BLOCKED ${name} did not finish: ${why}`);
		}
		const line = statusLine(lastText(final));
		return { content: [{ type: "text", text: line || `BLOCKED ${name} returned no status line` }], details: { turns } };
	}
}
