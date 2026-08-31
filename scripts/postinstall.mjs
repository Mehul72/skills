// npm postinstall. Runs the global layer for `npm install -g` only.
//
// A local `npm install` of this package as a dependency must not touch ~/.claude,
// ~/.codex, or ~/.gemini, so anything that is not a global install exits quietly.
// npx also lands here: it installs into a cache directory first, which is not a
// global install, so the install work is left to the `skills install` the user typed.
//
// This never fails the npm install. A broken postinstall that aborts `npm i -g`
// would be worse than no postinstall at all.

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { platform } from "node:process";

const lib = dirname(dirname(fileURLToPath(import.meta.url)));

const skip = (why) => {
  if (process.env.SKILLS_DEBUG) console.log(`skills: postinstall skipped, ${why}`);
  process.exit(0);
};

if (process.env.SKILLS_SKIP_POSTINSTALL === "1") skip("SKILLS_SKIP_POSTINSTALL=1");
if (process.env.CI) skip("running in CI");
if (platform === "win32") skip("the installer is a bash script");
if (process.env.npm_config_global !== "true") skip("not a global install");

console.log("\nskills: installing the global agent layer\n");

const r = spawnSync("bash", [join(lib, "bin", "skills"), "install"], {
  stdio: "inherit",
  env: process.env,
});

if (r.error || r.status !== 0) {
  console.log(
    `\nskills: the global layer did not install (${r.error?.message ?? `exit ${r.status}`}).` +
      `\n        The package itself is fine. Finish by hand with:  skills install\n`,
  );
  process.exit(0);
}

console.log("\nskills: done. Next, in each repo you work in:  skills init\n");
