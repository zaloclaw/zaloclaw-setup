#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const readline = require("readline/promises");

const REPOSITORIES = [
  {
    name: "zaloclaw-ui",
    url: "https://github.com/zaloclaw/zaloclaw-ui.git",
    folder: "zaloclaw-ui",
  },
  {
    name: "zaloclaw-infra",
    url: "https://github.com/zaloclaw/zaloclaw-infra.git",
    folder: "zaloclaw-infra",
  },
];

const STEP_TITLES = [
  ["platform", "Detect OS and permission context"],
  ["prerequisites", "Validate and install prerequisites"],
  ["clone", "Clone or prepare repositories"],
  ["env", "Collect and write infra .env"],
  ["infra", "Run macOS infra setup script"],
  ["ui", "Optional UI launch"],
];

function parseArgs(argv) {
  const parsed = {
    workspaceRoot: process.cwd(),
    sourceRoot: null,
    cloneMode: "prompt",
    provider: null,
    providerApiKey: null,
    litellmMasterKey: null,
    openclawConfigDir: null,
    launchUi: null,
    installMissingPrerequisites: true,
    infraScriptPath: null,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    const next = argv[i + 1];

    if (value === "--workspace-root" && next) {
      parsed.workspaceRoot = path.resolve(next);
      i += 1;
      continue;
    }

    if (value === "--source-root" && next) {
      parsed.sourceRoot = path.resolve(next);
      i += 1;
      continue;
    }

    if (value === "--clone-mode" && next) {
      parsed.cloneMode = next;
      i += 1;
      continue;
    }

    if (value === "--provider" && next) {
      parsed.provider = next;
      i += 1;
      continue;
    }

    if (value === "--provider-api-key" && next) {
      parsed.providerApiKey = next;
      i += 1;
      continue;
    }

    if (value === "--litellm-master-key" && next) {
      parsed.litellmMasterKey = next;
      i += 1;
      continue;
    }

    if (value === "--config-dir" && next) {
      parsed.openclawConfigDir = next;
      i += 1;
      continue;
    }

    if (value === "--infra-script-path" && next) {
      parsed.infraScriptPath = next;
      i += 1;
      continue;
    }

    if (value === "--launch-ui") {
      parsed.launchUi = true;
      continue;
    }

    if (value === "--no-launch-ui") {
      parsed.launchUi = false;
      continue;
    }

    if (value === "--install-missing-prerequisites") {
      parsed.installMissingPrerequisites = true;
      continue;
    }

    if (value === "--no-install-missing-prerequisites") {
      parsed.installMissingPrerequisites = false;
      continue;
    }
  }

  return parsed;
}

function isDirectory(targetPath) {
  try {
    return fs.statSync(targetPath).isDirectory();
  } catch {
    return false;
  }
}

function runCommand(command, args, options = {}) {
  const cwd = options.cwd || process.cwd();
  const shell = Boolean(options.shell);
  const inheritOutput = Boolean(options.inheritOutput);

  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd,
      shell,
      stdio: inheritOutput ? "inherit" : "pipe",
      env: options.env || process.env,
    });

    let stdout = "";
    let stderr = "";

    if (!inheritOutput) {
      if (child.stdout) {
        child.stdout.on("data", (chunk) => {
          stdout += chunk.toString();
        });
      }

      if (child.stderr) {
        child.stderr.on("data", (chunk) => {
          stderr += chunk.toString();
        });
      }
    }

    child.on("close", (code) => {
      resolve({ code: code == null ? 1 : code, stdout, stderr });
    });

    child.on("error", (error) => {
      resolve({ code: 1, stdout, stderr: String(error) });
    });
  });
}

function makeState(workspaceRoot) {
  return {
    startedAt: new Date().toISOString(),
    platform: {
      name: "macos",
      raw: process.platform,
      isWindows: false,
      isMac: true,
      isAdminLike: typeof process.getuid === "function" ? process.getuid() === 0 : false,
    },
    workspaceRoot,
    logs: [],
    blockedReasons: [],
    steps: STEP_TITLES.map(([id, title]) => ({
      id,
      title,
      status: "pending",
      retries: 0,
      checkpoints: [],
      lastError: null,
      startedAt: null,
      endedAt: null,
    })),
    setupCompletion: {
      status: "pending",
      completedAt: null,
    },
    uiRuntime: {
      status: "not-started",
      pid: null,
      exitCode: null,
      lastMessage: null,
    },
  };
}

function statePath(workspaceRoot) {
  return path.join(workspaceRoot, "setup-state.json");
}

function saveState(state) {
  fs.writeFileSync(statePath(state.workspaceRoot), JSON.stringify(state, null, 2), "utf8");
}

function getStep(state, id) {
  return state.steps.find((item) => item.id === id);
}

function setStepStatus(state, id, status, errorMessage) {
  const step = getStep(state, id);
  if (!step) {
    return;
  }

  if (status === "running") {
    step.startedAt = new Date().toISOString();
  }

  if (status === "done" || status === "failed" || status === "blocked") {
    step.endedAt = new Date().toISOString();
  }

  step.status = status;
  if (errorMessage) {
    step.lastError = errorMessage;
  }
}

function addCheckpoint(state, stepId, message) {
  const step = getStep(state, stepId);
  if (!step) {
    return;
  }

  step.checkpoints.push(`${new Date().toISOString()} ${message}`);
}

function addLog(state, level, message) {
  state.logs.push(`${new Date().toISOString()} [${level}] ${message}`);
  if (level === "error") {
    console.error(`ERROR: ${message}`);
    return;
  }

  if (level === "warn") {
    console.warn(`WARN: ${message}`);
    return;
  }

  console.log(message);
}

function printSummary(state, gatewayToken = null) {
  console.log("\n=== Setup Summary ===");
  for (const step of state.steps) {
    console.log(`- ${step.id}: ${step.status}`);
    if (step.lastError) {
      console.log(`  reason: ${step.lastError}`);
    }
  }

  console.log(`setup completion: ${state.setupCompletion.status}`);
  console.log(`ui runtime: ${state.uiRuntime.status}`);

  if (state.blockedReasons.length > 0) {
    console.log("blocked reasons:");
    for (const reason of state.blockedReasons) {
      console.log(`- ${reason}`);
    }
  }

  if (gatewayToken) {
    console.log("\n=== OpenClaw Gateway Token ===");
    console.log(`Token: ${gatewayToken}`);
    console.log("\nUse this token to connect to OpenClaw Gateway interface.");
  }
}

async function askYesNo(rl, prompt, defaultValue) {
  const suffix = defaultValue ? "[Y/n]" : "[y/N]";
  const answer = (await rl.question(`${prompt} ${suffix}: `)).trim().toLowerCase();
  if (!answer) {
    return defaultValue;
  }
  return answer === "y" || answer === "yes";
}

async function pickProvider(rl, args) {
  if (["openai", "google", "anthropic", "openrouter"].includes(String(args.provider || "").toLowerCase())) {
    return String(args.provider).toLowerCase();
  }

  console.log("Choose provider:");
  console.log("1) OpenAI");
  console.log("2) Google");
  console.log("3) Anthropic");
  console.log("4) OpenRouter");

  let value = "";
  while (!["1", "2", "3", "4"].includes(value)) {
    value = (await rl.question("Select provider (1/2/3/4): ")).trim();
  }

  if (value === "1") {
    return "openai";
  }

  if (value === "2") {
    return "google";
  }

  if (value === "3") {
    return "anthropic";
  }

  return "openrouter";
}

async function ensureProviderKey(rl, args, provider) {
  if (args.providerApiKey && args.providerApiKey.trim()) {
    return args.providerApiKey.trim();
  }

  const label = provider === "openai"
    ? "OPENAI_API_KEY"
    : provider === "google"
      ? "GOOGLE_API_KEY"
      : provider === "anthropic"
        ? "ANTHROPIC_API_KEY"
        : "OPENROUTER_API_KEY";
  let value = "";
  while (!value) {
    value = (await rl.question(`Enter ${label}: `)).trim();
  }
  return value;
}

async function ensureLitellmKey(rl, args) {
  if (args.litellmMasterKey && args.litellmMasterKey.trim()) {
    return args.litellmMasterKey.trim();
  }

  let value = "";
  while (!value) {
    value = (await rl.question("Enter LITELLM_MASTER_KEY: ")).trim();
  }
  return value;
}

async function ensureConfigDir(rl, args) {
  if (args.openclawConfigDir && args.openclawConfigDir.trim()) {
    return args.openclawConfigDir.trim();
  }

  const defaultDir = path.join(os.homedir(), ".openclaw_z");
  const entered = (await rl.question(`OPENCLAW_CONFIG_DIR [default: ${defaultDir}]: `)).trim();
  return entered || defaultDir;
}

async function commandExists(command) {
  const check = await runCommand("bash", ["-lc", `command -v ${command}`], { shell: false });
  return check.code === 0;
}

async function ensureHomebrew(state) {
  if (await commandExists("brew")) {
    return true;
  }

  addLog(state, "error", "Homebrew is required but not installed.");
  return false;
}

async function ensurePrerequisite(state, tool) {
  if (await commandExists(tool.command)) {
    return true;
  }

  addLog(state, "warn", `${tool.name} is missing.`);
  if (!state.runtime.installMissingPrerequisites) {
    addLog(state, "warn", `Automatic install disabled for ${tool.name}.`);
    return false;
  }

  addLog(state, "info", `Installing ${tool.name}...`);
  const install = await runCommand("bash", ["-lc", tool.install], { inheritOutput: true });
  if (install.code !== 0) {
    addLog(state, "warn", `${tool.name} install command failed with code ${install.code}.`);
    return false;
  }

  return commandExists(tool.command);
}

async function isDockerDesktopInstalled() {
  const check = await runCommand("open", ["-Ra", "Docker"], { shell: false });
  return check.code === 0;
}

function extractBrewBinaryConflictPath(output) {
  const match = output.match(/already a Binary at '([^']+)'/i);
  return match ? match[1] : null;
}

function moveConflictingBinaryAside(filePath) {
  try {
    const stat = fs.lstatSync(filePath);
    if (stat.isDirectory()) {
      return null;
    }

    const backupPath = `${filePath}.zaloclaw-backup-${Date.now()}`;
    fs.renameSync(filePath, backupPath);
    return backupPath;
  } catch {
    return null;
  }
}

async function ensureDockerDesktopInstalled(state) {
  if (await isDockerDesktopInstalled()) {
    return true;
  }

  addLog(state, "warn", "Docker Desktop app is not installed.");
  if (!state.runtime.installMissingPrerequisites) {
    addLog(state, "warn", "Automatic install disabled for Docker Desktop.");
    return false;
  }

  addLog(state, "info", "Installing Docker Desktop...");
  let install = await runCommand("bash", ["-lc", "brew install --cask docker-desktop"], {
    shell: false,
  });

  if (install.code !== 0) {
    const detail = `${install.stderr || ""}\n${install.stdout || ""}`;
    const conflictPath = extractBrewBinaryConflictPath(detail);

    if (conflictPath) {
      addLog(state, "warn", `Homebrew reported binary conflict at ${conflictPath}.`);
      const backupPath = moveConflictingBinaryAside(conflictPath);

      if (backupPath) {
        addLog(state, "info", `Moved conflicting file to ${backupPath}. Retrying Docker Desktop install...`);
        install = await runCommand("bash", ["-lc", "brew install --cask docker-desktop"], {
          shell: false,
        });

        if (install.code !== 0) {
          addLog(state, "warn", `Docker Desktop retry install failed with code ${install.code}.`);
          addLog(state, "warn", `You can restore the previous symlink with: mv \"${backupPath}\" \"${conflictPath}\"`);
          return false;
        }
      } else {
        addLog(
          state,
          "error",
          `Cannot auto-resolve conflict at ${conflictPath}. Remove or rename that file, then rerun setup.`,
        );
        return false;
      }
    } else {
      addLog(state, "warn", `Docker Desktop install command failed with code ${install.code}.`);
      const firstLine = (install.stderr || install.stdout || "").split(/\r?\n/).find(Boolean);
      if (firstLine) {
        addLog(state, "warn", `Install error: ${firstLine}`);
      }
      return false;
    }
  }

  return isDockerDesktopInstalled();
}

async function ensurePrerequisites(state) {
  const tools = [
    { name: "Git", command: "git", install: "brew install git" },
    { name: "Node.js", command: "node", install: "brew install node" },
    { name: "npm", command: "npm", install: "brew install node" },
  ];

  if (!(await ensureHomebrew(state))) {
    return ["Homebrew"];
  }

  const missing = [];
  for (const tool of tools) {
    const ok = await ensurePrerequisite(state, tool);
    if (!ok) {
      missing.push(tool.name);
    }
  }

  const hasDockerDesktop = await ensureDockerDesktopInstalled(state);
  if (!hasDockerDesktop) {
    missing.push("Docker Desktop");
    return missing;
  }

  if (!(await commandExists("docker"))) {
    addLog(
      state,
      "error",
      "Docker CLI command is unavailable even though Docker Desktop is installed. Open Docker Desktop once, then retry setup.",
    );
    missing.push("Docker CLI");
    return missing;
  }

  const dockerReady = await waitForDockerDaemonReady(state, {
    stepId: "prerequisites",
    waitSeconds: 120,
    intervalSeconds: 5,
  });

  if (!dockerReady) {
    missing.push("Docker daemon");
  }

  return missing;
}

function sleepMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isDockerFatalStartupError(detail) {
  if (!detail) {
    return false;
  }

  const normalized = detail.toLowerCase();
  const fatalMarkers = [
    "internal virtualization error",
    "the virtual machine stopped unexpectedly",
    "failed to run: running vm",
    "process terminated unexpectedly",
    "virtualization-framework failed to run",
  ];

  return fatalMarkers.some((marker) => normalized.includes(marker));
}

async function waitForDockerDaemonReady(state, options = {}) {
  const stepId = options.stepId || "infra";
  const waitSeconds = Number.isFinite(options.waitSeconds) ? options.waitSeconds : 120;
  const intervalSeconds = Number.isFinite(options.intervalSeconds) ? options.intervalSeconds : 5;
  const attempts = Math.max(1, Math.ceil(waitSeconds / intervalSeconds));

  let launchedDockerDesktop = false;

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const dockerInfo = await runCommand("docker", ["info"], { shell: false });
    if (dockerInfo.code === 0) {
      if (attempt > 1) {
        addLog(state, "info", "Docker daemon is ready. Continuing setup.");
        addCheckpoint(state, stepId, "Docker daemon became ready");
      }
      return true;
    }

    const detail = (dockerInfo.stderr || dockerInfo.stdout || "").trim();
    if (isDockerFatalStartupError(detail)) {
      const firstLine = detail.split(/\r?\n/)[0] || "Docker Desktop VM failed to start";
      addCheckpoint(state, stepId, `Docker fatal startup error: ${firstLine}`);
      addLog(
        state,
        "error",
        "Docker Desktop failed to start its VM (virtualization error). Open Docker Desktop, restart it, then retry setup. If it persists, reboot macOS and use Docker Desktop Troubleshoot -> Reset to factory defaults.",
      );
      return false;
    }

    if (attempt === 1) {
      addLog(state, "warn", "Docker daemon is not reachable yet. Waiting for Docker Desktop to become ready...");
      if (detail) {
        addCheckpoint(state, stepId, `Docker daemon check failed: ${detail.split(/\r?\n/)[0]}`);
      }

      const launch = await runCommand("open", ["-a", "Docker"], { shell: false });
      if (launch.code === 0) {
        launchedDockerDesktop = true;
        addLog(state, "info", "Requested Docker Desktop launch.");
      }
    }

    if (attempt < attempts) {
      addLog(state, "info", `Waiting for Docker daemon (${attempt}/${attempts})...`);
      await sleepMs(intervalSeconds * 1000);
    }
  }

  addLog(
    state,
    "error",
    launchedDockerDesktop
      ? "Docker Desktop did not become ready in time. Please wait until Docker is fully running, then retry setup."
      : "Docker daemon is not reachable. Start Docker Desktop, wait until it is running, then retry setup.",
  );

  const finalCheck = await runCommand("docker", ["info"], { shell: false });
  const finalDetail = (finalCheck.stderr || finalCheck.stdout || "").trim();
  if (finalDetail) {
    addCheckpoint(state, stepId, `Docker daemon still unavailable: ${finalDetail.split(/\r?\n/)[0]}`);
  }

  return false;
}

async function decideCloneMode(rl, args) {
  const valid = ["reuse", "replace", "fail"];
  if (valid.includes(args.cloneMode)) {
    return args.cloneMode;
  }

  console.log("When repository directory already exists:");
  console.log("1) Reuse existing folder");
  console.log("2) Replace existing folder");
  console.log("3) Fail and stop setup");

  let value = "";
  while (!["1", "2", "3"].includes(value)) {
    value = (await rl.question("Select mode (1/2/3): ")).trim();
  }

  if (value === "1") {
    return "reuse";
  }

  if (value === "2") {
    return "replace";
  }

  return "fail";
}

async function ensureRepo(state, repo, cloneMode) {
  const targetPath = path.join(state.workspaceRoot, repo.folder);
  const sourceRoot = state.runtime.sourceRoot;
  const sourcePath = sourceRoot ? path.join(sourceRoot, repo.folder) : null;

  if (fs.existsSync(targetPath)) {
    if (cloneMode === "reuse") {
      addCheckpoint(state, "clone", `${repo.folder}: reused existing folder`);
      return true;
    }

    if (cloneMode === "replace") {
      fs.rmSync(targetPath, { recursive: true, force: true });
      addCheckpoint(state, "clone", `${repo.folder}: replaced existing folder`);
    } else {
      addCheckpoint(state, "clone", `${repo.folder}: exists and clone mode is fail`);
      return false;
    }
  }

  if (sourcePath && isDirectory(sourcePath)) {
    fs.cpSync(sourcePath, targetPath, { recursive: true });
    addCheckpoint(state, "clone", `${repo.folder}: copied from local source ${sourcePath}`);
    return true;
  }

  const clone = await runCommand("git", ["clone", repo.url, repo.folder], {
    cwd: state.workspaceRoot,
    shell: false,
    inheritOutput: true,
  });

  if (clone.code !== 0) {
    addCheckpoint(state, "clone", `${repo.folder}: clone failed with code ${clone.code}`);
    return false;
  }

  addCheckpoint(state, "clone", `${repo.folder}: cloned`);
  return true;
}

function providerKeyName(provider) {
  if (provider === "openai") {
    return "OPENAI_API_KEY";
  }
  if (provider === "google") {
    return "GOOGLE_API_KEY";
  }
  if (provider === "anthropic") {
    return "ANTHROPIC_API_KEY";
  }
  return "OPENROUTER_API_KEY";
}

function quoteIfNeeded(value) {
  return value.includes(" ") ? `"${value.replace(/"/g, '\\"')}"` : value;
}

function renderEnvLines(sourceLines, overrides) {
  const output = [];
  const seen = new Set();

  for (const line of sourceLines) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      output.push(line);
      continue;
    }

    const key = match[1];
    if (!(key in overrides)) {
      output.push(line);
      continue;
    }

    output.push(`${key}=${quoteIfNeeded(String(overrides[key]))}`);
    seen.add(key);
  }

  for (const [key, value] of Object.entries(overrides)) {
    if (!seen.has(key)) {
      output.push(`${key}=${quoteIfNeeded(String(value))}`);
    }
  }

  return `${output.join("\n")}\n`;
}

function readEnvValue(filePath, key) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  const content = fs.readFileSync(filePath, "utf8");
  const match = content.match(new RegExp(`^\\s*${key}\\s*=\\s*(.*)$`, "m"));
  if (!match) {
    return null;
  }
  let value = match[1].trim();
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    value = value.slice(1, -1);
  }
  return value;
}

function syncUiGatewayTokenFromInfra(state, options = {}) {
  const { stepId = "env", requireToken = false } = options;
  const infraEnvPath = path.join(state.workspaceRoot, "zaloclaw-infra", ".env");
  const uiDir = path.join(state.workspaceRoot, "zaloclaw-ui");

  if (!fs.existsSync(uiDir)) {
    addLog(state, "info", "Skipping UI env sync: zaloclaw-ui directory not found");
    addCheckpoint(state, stepId, "Skipped UI env sync (zaloclaw-ui missing)");
    return;
  }

  const gatewayToken = readEnvValue(infraEnvPath, "OPENCLAW_GATEWAY_TOKEN");
  if (!gatewayToken) {
    const message = `OPENCLAW_GATEWAY_TOKEN is missing in ${infraEnvPath}`;
    if (requireToken) {
      throw new Error(message);
    }
    addLog(state, "warn", `Skipping UI token sync: ${message}`);
    return;
  }

  const uiEnvExamplePath = path.join(uiDir, ".env.example");
  let uiEnvContent;
  if (fs.existsSync(uiEnvExamplePath)) {
    const uiSource = fs.readFileSync(uiEnvExamplePath, "utf8").split(/\r?\n/);
    uiEnvContent = renderEnvLines(uiSource, { NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN: gatewayToken });
  } else {
    uiEnvContent = `NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN=${quoteIfNeeded(gatewayToken)}\n`;
  }

  const uiEnvPath = path.join(uiDir, ".env");
  fs.writeFileSync(uiEnvPath, uiEnvContent, "utf8");
  addCheckpoint(state, stepId, `Wrote ${uiEnvPath}`);
}

function ensureUiGatewayTokenReady(state, stepId = "infra") {
  const infraEnvPath = path.join(state.workspaceRoot, "zaloclaw-infra", ".env");
  const uiEnvPath = path.join(state.workspaceRoot, "zaloclaw-ui", ".env");

  const infraToken = readEnvValue(infraEnvPath, "OPENCLAW_GATEWAY_TOKEN");
  if (!infraToken) {
    throw new Error(`OPENCLAW_GATEWAY_TOKEN is missing in ${infraEnvPath}`);
  }

  const uiToken = readEnvValue(uiEnvPath, "NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN");
  if (!uiToken) {
    throw new Error(`NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN is missing in ${uiEnvPath}`);
  }

  if (uiToken !== infraToken) {
    throw new Error(
      `Gateway token mismatch between ${infraEnvPath} and ${uiEnvPath}. Run sync before docker compose.`
    );
  }

  addCheckpoint(state, stepId, "Verified UI gateway token matches infra .env");
}

function writeEnv(state) {
  const infraDir = path.join(state.workspaceRoot, "zaloclaw-infra");
  const envExamplePath = path.join(infraDir, ".env.example");
  if (!fs.existsSync(envExamplePath)) {
    throw new Error(`Missing ${envExamplePath}`);
  }

  const source = fs.readFileSync(envExamplePath, "utf8").split(/\r?\n/);
  const selectedProviderKey = providerKeyName(state.runtime.provider);
  const workspaceDir = path.join(state.runtime.openclawConfigDir, "workspace");

  const overrides = {
    OPENCLAW_CONFIG_DIR: state.runtime.openclawConfigDir,
    OPENCLAW_WORKSPACE_DIR: workspaceDir,
    OPENAI_API_KEY: "",
    GOOGLE_API_KEY: "",
    ANTHROPIC_API_KEY: "",
    OPENROUTER_API_KEY: "",
    LITELLM_MASTER_KEY: state.runtime.litellmMasterKey,
    [selectedProviderKey]: state.runtime.providerApiKey,
  };

  const envPath = path.join(infraDir, ".env");
  fs.writeFileSync(envPath, renderEnvLines(source, overrides), "utf8");

  const finalContent = fs.readFileSync(envPath, "utf8");
  const required = ["OPENCLAW_CONFIG_DIR", "OPENCLAW_WORKSPACE_DIR", "LITELLM_MASTER_KEY", selectedProviderKey];
  for (const key of required) {
    if (!new RegExp(`^${key}=`, "m").test(finalContent)) {
      throw new Error(`Missing required key in .env: ${key}`);
    }
  }

  addCheckpoint(state, "env", `Wrote ${envPath}`);
  syncUiGatewayTokenFromInfra(state, { stepId: "env", requireToken: false });
}

function cleanupOpenClawConfigDir(state, stepId = "infra") {
  const configDir = state.runtime.openclawConfigDir;
  if (!configDir) {
    throw new Error("OPENCLAW_CONFIG_DIR is empty.");
  }

  const resolved = path.resolve(configDir);
  const rootPath = path.parse(resolved).root;
  if (resolved === rootPath) {
    throw new Error(`Refusing to remove root path as OPENCLAW_CONFIG_DIR: ${resolved}`);
  }

  if (fs.existsSync(resolved)) {
    addLog(state, "info", `Cleaning OpenClaw directory before infra setup: ${resolved}`);
    fs.rmSync(resolved, { recursive: true, force: true });
    addCheckpoint(state, stepId, `Removed existing OpenClaw directory ${resolved}`);
  } else {
    addCheckpoint(state, stepId, `OpenClaw directory did not exist: ${resolved}`);
  }

  fs.mkdirSync(resolved, { recursive: true });
  addCheckpoint(state, stepId, `Prepared clean OpenClaw directory ${resolved}`);
}

async function findOpenClawGatewayContainer(state) {
  try {
    addLog(state, "info", "Finding OpenClaw gateway container...");
    const result = await runCommand("docker", ["ps", "--format", "{{.Names}}"], {
      shell: false,
    });
    if (result.code !== 0) {
      addLog(state, "warn", "Failed to list docker containers");
      return null;
    }
    const containers = result.stdout
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
    const gatewayContainer = containers.find((name) =>
      name.toLowerCase().includes("openclaw-gateway")
    );
    if (gatewayContainer) {
      addLog(state, "info", `Found OpenClaw gateway container: ${gatewayContainer}`);
      return gatewayContainer;
    }
    addLog(state, "warn", "No container with 'openclaw-gateway' pattern found");
    return null;
  } catch (error) {
    addLog(state, "warn", `Error finding container: ${String(error)}`);
    return null;
  }
}

function updateUiEnvContainerName(state, uiDir, containerName) {
  try {
    const uiEnvPath = path.join(uiDir, ".env");
    if (!fs.existsSync(uiDir)) {
      addLog(state, "info", "Skipping UI container env: zaloclaw-ui directory not found");
      return false;
    }
    if (!fs.existsSync(uiEnvPath)) {
      addLog(state, "info", "Skipping UI container env: .env not found");
      return false;
    }
    const uiEnvContent = fs.readFileSync(uiEnvPath, "utf8");
    const lines = uiEnvContent.split("\n");
    const outputLines = [];
    let found = false;
    for (const line of lines) {
      if (line.match(/^\s*OPENCLAW_GATEWAY_CONTAINER\s*=/)) {
        outputLines.push(`OPENCLAW_GATEWAY_CONTAINER=${containerName}`);
        found = true;
      } else {
        outputLines.push(line);
      }
    }
    if (!found) {
      outputLines.push(`OPENCLAW_GATEWAY_CONTAINER=${containerName}`);
    }
    fs.writeFileSync(uiEnvPath, outputLines.join("\n") + "\n", "utf8");
    addCheckpoint(state, "infra", `Updated UI .env with OPENCLAW_GATEWAY_CONTAINER=${containerName}`);
    addLog(state, "info", `Updated zaloclaw-ui .env: OPENCLAW_GATEWAY_CONTAINER=${containerName}`);
    return true;
  } catch (error) {
    addLog(state, "warn", `Failed to update UI .env with container name: ${String(error)}`);
    return false;
  }
}

async function runInfra(state) {
  const infraDir = path.join(state.workspaceRoot, "zaloclaw-infra");
  const scriptPath = state.runtime.infraScriptPath || path.join(infraDir, "zaloclaw-docker-setup.sh");

  cleanupOpenClawConfigDir(state, "infra");

  if (!(await waitForDockerDaemonReady(state, { stepId: "infra", waitSeconds: 60, intervalSeconds: 5 }))) {
    throw new Error("Docker daemon is not running. Please start Docker Desktop and retry.");
  }

  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Infra script not found: ${scriptPath}`);
  }

  const run = await runCommand("bash", [scriptPath], {
    cwd: infraDir,
    shell: false,
    inheritOutput: true,
    env: {
      ...process.env,
      ZALOC_SETUP_CONTRACT_VERSION: "1",
    },
  });

  if (run.code !== 0) {
    throw new Error(`Infra script exited with code ${run.code}`);
  }

  // Infra setup may rewrite OPENCLAW_GATEWAY_TOKEN; sync UI .env from final infra .env.
  syncUiGatewayTokenFromInfra(state, { stepId: "infra", requireToken: true });
  ensureUiGatewayTokenReady(state, "infra");

  await startUiComposeServicesIfPresent(state, infraDir);
  await startUiComposeRepositoryIfPresent(state);

  addCheckpoint(state, "infra", "Infra script completed");
}

function uiRepoCandidates(state) {
  return [path.join(state.workspaceRoot, "zaloclaw-ui")];
}

async function startUiComposeRepositoryIfPresent(state) {
  for (const uiDir of uiRepoCandidates(state)) {
    const composePath = path.join(uiDir, "docker-compose.yml");
    if (!fs.existsSync(composePath)) {
      addLog(state, "info", `UI compose not found at ${composePath}`);
      continue;
    }

    addLog(state, "info", `Starting UI compose stack: docker compose -f ${composePath} up -d`);

    const up = await runCommand("docker", ["compose", "-f", composePath, "up", "-d"], {
      cwd: uiDir,
      shell: false,
      inheritOutput: true,
    });

    if (up.code !== 0) {
      throw new Error(`Failed to start UI compose stack in ${uiDir}`);
    }

    addLog(state, "info", `UI compose stack started from ${composePath}`);
    addCheckpoint(state, "infra", `Started UI compose stack from ${composePath}`);
    return;
  }

  addLog(state, "info", "No UI repository compose file detected");
  addCheckpoint(state, "infra", "No UI repository compose file detected");
}

function pickUiComposeServices(services) {
  const preferred = ["zaloclaw-ui", "ui", "frontend", "dashboard"];
  const normalized = services.map((service) => service.trim()).filter(Boolean);
  const selected = [];

  for (const name of preferred) {
    if (normalized.includes(name)) {
      selected.push(name);
    }
  }

  if (selected.length > 0) {
    return selected;
  }

  return normalized.filter((service) => /ui|front|dashboard/i.test(service));
}

async function startUiComposeServicesIfPresent(state, infraDir) {
  const composeFiles = [path.join(infraDir, "docker-compose.yml")];
  const extraCompose = path.join(infraDir, "docker-compose.extra.yml");
  if (fs.existsSync(extraCompose)) {
    composeFiles.push(extraCompose);
  }

  const composeArgs = composeFiles.flatMap((filePath) => ["-f", filePath]);
  const list = await runCommand("docker", ["compose", ...composeArgs, "config", "--services"], {
    cwd: infraDir,
    shell: false,
  });

  if (list.code !== 0) {
    addLog(state, "warn", "Skipping infra compose UI service start: unable to list compose services");
    addCheckpoint(state, "infra", "Skipped compose UI service start (unable to list services)");
    return;
  }

  const services = list.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const uiServices = pickUiComposeServices(services);

  if (uiServices.length === 0) {
    addLog(state, "info", "No UI-related service found in infra compose");
    addCheckpoint(state, "infra", "No UI-related compose service detected");
    return;
  }

  addLog(state, "info", `Starting infra compose UI service(s): ${uiServices.join(", ")}`);

  const up = await runCommand("docker", ["compose", ...composeArgs, "up", "-d", ...uiServices], {
    cwd: infraDir,
    shell: false,
    inheritOutput: true,
  });

  if (up.code !== 0) {
    throw new Error(`Failed to start compose UI services (${uiServices.join(", ")})`);
  }

  addLog(state, "info", `Started infra compose UI service(s): ${uiServices.join(", ")}`);
  addCheckpoint(state, "infra", `Started compose UI services: ${uiServices.join(", ")}`);
}

async function maybeLaunchUi(state, rl, args) {
  const uiDir = path.join(state.workspaceRoot, "zaloclaw-ui");

  let launch = args.launchUi;
  if (launch == null) {
    launch = await askYesNo(rl, "Setup complete. Start UI now with npm run dev?", false);
  }

  if (!launch) {
    state.uiRuntime.status = "skipped";
    state.uiRuntime.lastMessage = "User skipped UI launch";
    return;
  }

  if (!fs.existsSync(path.join(uiDir, "package.json"))) {
    state.uiRuntime.status = "failed";
    state.uiRuntime.lastMessage = "Cannot start UI: package.json not found";
    return;
  }

  state.uiRuntime.status = "running";
  const child = spawn("npm", ["run", "dev"], {
    cwd: uiDir,
    detached: true,
    stdio: "ignore",
  });

  child.unref();
  state.uiRuntime.pid = child.pid || null;
  state.uiRuntime.status = "running";
  state.uiRuntime.lastMessage = "UI launched in background";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (process.platform !== "darwin") {
    console.error("This installer flow supports macOS only.");
    process.exit(1);
  }

  fs.mkdirSync(args.workspaceRoot, { recursive: true });
  const state = makeState(args.workspaceRoot);
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    console.log("\n=== ZaloClaw Local Setup (macOS Installer) ===");
    console.log(`Workspace: ${state.workspaceRoot}`);

    const provider = await pickProvider(rl, args);
    const providerApiKey = await ensureProviderKey(rl, args, provider);
    const litellmMasterKey = await ensureLitellmKey(rl, args);
    const openclawConfigDir = await ensureConfigDir(rl, args);
    const cloneMode = await decideCloneMode(rl, args);

    state.runtime = {
      provider,
      providerApiKey,
      litellmMasterKey,
      openclawConfigDir,
      cloneMode,
      sourceRoot: args.sourceRoot,
      launchUi: args.launchUi,
      installMissingPrerequisites: args.installMissingPrerequisites,
      infraScriptPath: args.infraScriptPath,
    };

    saveState(state);

    setStepStatus(state, "platform", "running");
    addCheckpoint(state, "platform", "Detected platform macOS");
    addCheckpoint(state, "platform", `Admin-like permissions: ${state.platform.isAdminLike}`);
    setStepStatus(state, "platform", "done");
    saveState(state);

    setStepStatus(state, "prerequisites", "running");
    const missing = await ensurePrerequisites(state);
    if (missing.length > 0) {
      const reason = `Missing prerequisites after checks/install attempts: ${missing.join(", ")}`;
      setStepStatus(state, "prerequisites", "blocked", reason);
      state.blockedReasons.push(reason);
      saveState(state);
      printSummary(state);
      process.exit(1);
    }

    addCheckpoint(state, "prerequisites", "All prerequisites available");
    setStepStatus(state, "prerequisites", "done");
    saveState(state);

    setStepStatus(state, "clone", "running");
    for (const repo of REPOSITORIES) {
      const ok = await ensureRepo(state, repo, cloneMode);
      if (!ok) {
        const reason = `Clone workflow failed for ${repo.folder}`;
        setStepStatus(state, "clone", "blocked", reason);
        state.blockedReasons.push(reason);
        saveState(state);
        printSummary(state);
        process.exit(1);
      }
    }

    setStepStatus(state, "clone", "done");
    saveState(state);

    setStepStatus(state, "env", "running");
    writeEnv(state);
    setStepStatus(state, "env", "done");
    saveState(state);

    setStepStatus(state, "infra", "running");
    await runInfra(state);
    setStepStatus(state, "infra", "done");
    saveState(state);

    let gatewayToken = null;
    try {
      const infraDir = path.join(state.workspaceRoot, "zaloclaw-infra");
      const infraEnvPath = path.join(infraDir, ".env");
      gatewayToken = readEnvValue(infraEnvPath, "OPENCLAW_GATEWAY_TOKEN");
      if (gatewayToken) {
        addLog(state, "info", `OpenClaw Gateway Token: ${gatewayToken}`);
      }
    } catch (error) {
      addLog(state, "warn", `Could not read gateway token: ${String(error)}`);
    }

    try {
      const containerName = await findOpenClawGatewayContainer(state);
      if (containerName) {
        const uiDir = path.join(state.workspaceRoot, "zaloclaw-ui");
        if (fs.existsSync(uiDir)) {
          updateUiEnvContainerName(state, uiDir, containerName);
        }
      }
    } catch (error) {
      addLog(state, "warn", `Could not update UI container name: ${String(error)}`);
    }

    setStepStatus(state, "ui", "running");
    await maybeLaunchUi(state, rl, args);
    setStepStatus(state, "ui", "done");

    state.setupCompletion.status = "complete";
    state.setupCompletion.completedAt = new Date().toISOString();
    saveState(state);

    printSummary(state, gatewayToken);
  } catch (error) {
    const message = String(error && error.message ? error.message : error);
    addLog(state, "error", `Unexpected setup error: ${message}`);

    const running = state.steps.find((step) => step.status === "running");
    if (running) {
      setStepStatus(state, running.id, "failed", message);
    }

    state.blockedReasons.push(message);
    state.setupCompletion.status = "failed";
    saveState(state);
    printSummary(state);
    process.exit(1);
  } finally {
    rl.close();
  }
}

main();
