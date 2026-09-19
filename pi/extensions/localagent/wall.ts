// The TDD wall for a dispatched localagent agent: blocks read/grep/find/ls on paths matching the
// deny globs in LOCALAGENT_WALL, except paths the brief handed over (a wall drop). Loaded only into
// that child by ./index.ts, which takes the globs from the agent's OpenCode `permission.read`.
// bash is not covered, as in OpenCode: running the tests is the point. docs/dev.md#localagent-workflow.
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// `**/` spans zero or more directories, `**` anything, `*` and `?` stay inside one segment.
function globToRegExp(glob: string): RegExp {
	let re = "";
	for (let i = 0; i < glob.length; i++) {
		const c = glob[i];
		if (c === "*" && glob[i + 1] === "*") {
			i++;
			if (glob[i + 1] === "/") {
				i++;
				re += "(?:.*/)?";
			} else re += ".*";
		} else if (c === "*") re += "[^/]*";
		else if (c === "?") re += "[^/]";
		else re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
	}
	return new RegExp(`^${re}$`);
}

// A directory counts as walled when what it contains is: `ls tests` shows test names.
export function denies(globs: string[], cwd: string, target: string): boolean {
	const abs = path.resolve(cwd, target);
	const rel = path.relative(cwd, abs).split(path.sep).join("/");
	// Relative to the project, or a project that lives under some tests/ would wall itself off.
	const candidates = [rel.startsWith("..") ? abs.slice(1) : rel];
	return globs.map(globToRegExp).some((re) => candidates.some((c) => re.test(c) || re.test(`${c}/_`)));
}

export default function (pi: ExtensionAPI) {
	const { deny = [], allow = [] } = JSON.parse(process.env.LOCALAGENT_WALL ?? "{}") as { deny?: string[]; allow?: string[] };
	if (!deny.length) return;

	pi.on("tool_call", async (event, ctx) => {
		if (!["read", "grep", "find", "ls"].includes(event.toolName)) return;
		const target = String((event.input as { path?: string }).path ?? ".");
		if (allow.includes(path.resolve(ctx.cwd, target)) || !denies(deny, ctx.cwd, target)) return;
		return {
			block: true,
			reason: `${target} is test source, behind the wall. Run the tests and work from what they print.`,
		};
	});
}
