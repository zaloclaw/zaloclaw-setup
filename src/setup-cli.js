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

const FALLBACK_ENV_FIELDS = [
  "OPENCLAW_API_URL",
  "OPENCLAW_API_KEY",
  "OPENCLAW_ENVIRONMENT",
];

const STEP_TITLES = [
  ["platform", "Detect OS and permission context"],
  ["prerequisites", "Validate and install prerequisites"],
  ["clone", "Clone or prepare repositories"],
  ["env", "Collect and write infra .env"],
  ["infra", "Run platform-specific infra setup script"],
  ["ui", "Optional UI launch"],
];

function makeState(platformInfo, workspaceRoot) {
  return {
    startedAt: new Date().toISOString(),
    platform: platformInfo,
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

function getStep(state, id) {
  return state.steps.find((step) => step.id === id);
}

function setStepStatus(state, id, status, meta) {
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
  if (meta && meta.error) {
    step.lastError = meta.error;
  }
}

function addCheckpoint(state, id, message) {
  const step = getStep(state, id);
  if (!step) {
    return;
  }
  step.checkpoints.push(`${new Date().toISOString()} ${message}`);
}

function addLog(state, level, message) {
  const entry = `${new Date().toISOString()} [${level}] ${message}`;
  state.logs.push(entry);
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

function printHeader(state) {
  const platformName = state.platform.name;
  const adminText = state.platform.isAdminLike
    ? "admin-like permissions detected"
    : "admin-like permissions not detected";
  console.log("\n=== ZaloClaw Local Setup ===");
  console.log(`Workspace: ${state.workspaceRoot}`);
  console.log(`Platform: ${platformName} (${adminText})\n`);
}

function printStepSummary(state, gatewayToken = null) {
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

function stateSnapshotPath(workspaceRoot) {
  return path.join(workspaceRoot, "setup-state.json");
}

function persistState(state) {
  const output = JSON.stringify(state, null, 2);
  fs.writeFileSync(stateSnapshotPath(state.workspaceRoot), output, "utf8");
}

function parseYesNo(input, defaultValue) {
  const value = (input || "").trim().toLowerCase();
  if (!value) {
    return defaultValue;
  }
  return value === "y" || value === "yes";
}

async function askYesNo(rl, message, defaultValue) {
  const suffix = defaultValue ? "[Y/n]" : "[y/N]";
  const answer = await rl.question(`${message} ${suffix}: `);
  return parseYesNo(answer, defaultValue);
}

function commandExists(command, isWindows) {
  const checker = isWindows ? "where" : "command -v";
  return runCommand(checker, [command], { shell: !isWindows }).then((result) => result.code === 0);
}

function runCommand(command, args, options) {
  const useShell = Boolean(options && options.shell);
  const cwd = options && options.cwd ? options.cwd : process.cwd();
  const inheritOutput = Boolean(options && options.inheritOutput);
  const env = options && options.env ? options.env : process.env;

  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd,
      env,
      shell: useShell,
      stdio: inheritOutput ? "inherit" : "pipe",
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
      resolve({ code: code === null ? 1 : code, stdout, stderr });
    });

    child.on("error", (error) => {
      resolve({ code: 1, stdout, stderr: String(error) });
    });
  });
}

async function detectPlatformInfo() {
  const platform = process.platform;
  const isWindows = platform === "win32";
  const isMac = platform === "darwin";

  let isAdminLike = false;
  if (isWindows) {
    const adminCheck = await runCommand(
      "powershell",
      [
        "-NoProfile",
        "-Command",
        "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)",
      ],
      { shell: false }
    );
    isAdminLike = adminCheck.code === 0 && adminCheck.stdout.trim().toLowerCase() === "true";
  } else if (typeof process.getuid === "function") {
    isAdminLike = process.getuid() === 0;
  }

  let name = "linux";
  if (isWindows) {
    name = "windows";
  } else if (isMac) {
    name = "macos";
  }

  return {
    name,
    raw: platform,
    isWindows,
    isMac,
    isAdminLike,
  };
}

function installersForTool(tool, platformInfo) {
  const isWindows = platformInfo.isWindows;
  const isMac = platformInfo.isMac;

  if (isMac) {
    if (tool === "docker") {
      return {
        command: "brew install --cask docker",
        docs: "https://docs.docker.com/desktop/setup/install/mac-install/",
      };
    }
    if (tool === "git") {
      return {
        command: "brew install git",
        docs: "https://git-scm.com/download/mac",
      };
    }
    return {
      command: "brew install node",
      docs: "https://nodejs.org/en/download",
    };
  }

  if (isWindows) {
    if (tool === "docker") {
      return {
        command: "winget install --id Docker.DockerDesktop -e",
        docs: "https://docs.docker.com/desktop/setup/install/windows-install/",
      };
    }
    if (tool === "git") {
      return {
        command: "winget install --id Git.Git -e",
        docs: "https://git-scm.com/download/win",
      };
    }
    return {
      command: "winget install --id OpenJS.NodeJS.LTS -e",
      docs: "https://nodejs.org/en/download",
    };
  }

  return {
    command: "",
    docs: "",
  };
}

async function checkPrerequisites(platformInfo) {
  const isWindows = platformInfo.isWindows;

  const checks = [
    { id: "git", label: "Git", command: "git" },
    { id: "node", label: "Node.js", command: "node" },
    { id: "npm", label: "npm", command: "npm" },
  ];

  const results = [];
  for (const check of checks) {
    const exists = await commandExists(check.command, isWindows);
    results.push({
      id: check.id,
      label: check.label,
      exists,
    });
  }

  const dockerResult = await runCommand("docker", ["--version"], { shell: false });
  results.push({
    id: "docker",
    label: "Docker Desktop",
    exists: dockerResult.code === 0,
  });

  return results;
}

async function resolveMissingPrerequisites(state, rl) {
  const missing = (await checkPrerequisites(state.platform)).filter((item) => !item.exists);
  if (missing.length === 0) {
    return [];
  }

  addLog(state, "warn", `Missing prerequisites: ${missing.map((item) => item.label).join(", ")}`);

  for (const tool of missing) {
    const installer = installersForTool(tool.id, state.platform);
    addLog(state, "info", `Install guidance for ${tool.label}:`);
    if (installer.command) {
      addLog(state, "info", `- command: ${installer.command}`);
    }
    if (installer.docs) {
      addLog(state, "info", `- docs: ${installer.docs}`);
    }

    const shouldRun = await askYesNo(rl, `Try to run install command for ${tool.label} automatically?`, false);
    if (shouldRun && installer.command) {
      const run = await runCommand(installer.command, [], { shell: true, inheritOutput: true });
      if (run.code !== 0) {
        addLog(state, "warn", `${tool.label} install command returned code ${run.code}`);
      }
    }

    const latestCheck = (await checkPrerequisites(state.platform)).find((item) => item.id === tool.id);
    if (!latestCheck || !latestCheck.exists) {
      addLog(state, "warn", `${tool.label} is still unavailable after install attempt.`);
    } else {
      addLog(state, "info", `${tool.label} is now available.`);
    }
  }

  return (await checkPrerequisites(state.platform)).filter((item) => !item.exists);
}

async function ensureRepo(state, rl, repo) {
  const targetPath = path.join(state.workspaceRoot, repo.folder);

  if (fs.existsSync(targetPath)) {
    addLog(state, "warn", `${repo.folder} already exists at ${targetPath}`);
    const decision = await rl.question("Choose action: [r]euse, [x] replace, [c] cancel: ");
    const normalized = (decision || "").trim().toLowerCase();

    if (normalized === "c") {
      return {
        ok: false,
        skipped: true,
        message: `${repo.folder} canceled by user`,
      };
    }

    if (normalized === "x") {
      fs.rmSync(targetPath, { recursive: true, force: true });
      addLog(state, "info", `Removed existing folder ${repo.folder}`);
    }

    if (normalized === "r") {
      return {
        ok: true,
        reused: true,
        message: `${repo.folder} reused`,
      };
    }

    if (!["r", "x", "c"].includes(normalized)) {
      return {
        ok: false,
        skipped: true,
        message: `Invalid decision for ${repo.folder}`,
      };
    }
  }

  addLog(state, "info", `Cloning ${repo.url} into ${repo.folder}`);
  const result = await runCommand("git", ["clone", repo.url, repo.folder], {
    cwd: state.workspaceRoot,
    shell: false,
  });

  if (result.code !== 0) {
    return {
      ok: false,
      skipped: false,
      message: `Clone failed for ${repo.folder}: ${result.stderr.trim()}`,
    };
  }

  return {
    ok: true,
    reused: false,
    message: `${repo.folder} cloned`,
  };
}

async function cloneRepositories(state, rl) {
  const results = [];
  let pending = [...REPOSITORIES];

  while (pending.length > 0) {
    const failed = [];
    for (const repo of pending) {
      const repoResult = await ensureRepo(state, rl, repo);
      results.push({ repo: repo.name, ...repoResult });
      if (!repoResult.ok) {
        failed.push(repo);
      }
    }

    if (failed.length === 0) {
      break;
    }

    const retry = await askYesNo(
      rl,
      `Retry failed clones (${failed.map((item) => item.folder).join(", ")})?`,
      true
    );

    if (!retry) {
      return {
        ok: false,
        results,
      };
    }

    pending = failed;
  }

  return {
    ok: true,
    results,
  };
}

function parseEnvTemplate(templateContent) {
  const lines = templateContent.split(/\r?\n/);
  const fields = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      continue;
    }

    const key = match[1];
    const value = match[2].trim();
    const required = value === "" || value.includes("<") || value.includes("changeme");

    fields.push({ key, defaultValue: value, required });
  }

  return fields;
}

function readEnvValue(filePath, key) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf8");
  const pattern = new RegExp(`^${key}=(.*)$`, "m");
  const match = content.match(pattern);
  if (!match) {
    return null;
  }
  let value = match[1].trim();
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    value = value.slice(1, -1);
  }
  return value;
}

async function collectEnvValues(state, rl, infraDir, prePopulatedValues = {}) {
  const templateCandidates = [".env.example", ".env.template", "example.env"];
  let fields = [];

  for (const file of templateCandidates) {
    const candidate = path.join(infraDir, file);
    if (!fs.existsSync(candidate)) {
      continue;
    }
    const content = fs.readFileSync(candidate, "utf8");
    fields = parseEnvTemplate(content);
    if (fields.length > 0) {
      addLog(state, "info", `Using env template: ${file}`);
      break;
    }
  }

  if (fields.length === 0) {
    addLog(state, "warn", "No env template discovered. Falling back to default required fields.");
    fields = FALLBACK_ENV_FIELDS.map((key) => ({ key, defaultValue: "", required: true }));
  }

  const output = [];
  for (const field of fields) {
    let valid = false;
    let value = "";
    const prePopulated = prePopulatedValues[field.key];

    while (!valid) {
      const defaultValue = prePopulated || field.defaultValue;
      const defaultSuffix = defaultValue ? ` [default: ${defaultValue}]` : "";
      const answer = await rl.question(`Value for ${field.key}${defaultSuffix}: `);
      value = answer.trim() || defaultValue;
      if (field.required && !value) {
        addLog(state, "warn", `${field.key} is required.`);
        continue;
      }
      valid = true;
    }

    output.push({ key: field.key, value });
  }

  return output;
}

function serializeEnv(entries) {
  return `${entries
    .map((entry) => {
      const safeValue = entry.value.includes(" ") ? `"${entry.value.replace(/"/g, '\\"')}"` : entry.value;
      return `${entry.key}=${safeValue}`;
    })
    .join("\n")}\n`;
}

function verifyEnvFile(filePath, entries) {
  if (!fs.existsSync(filePath)) {
    return { ok: false, reason: "File not written" };
  }

  const content = fs.readFileSync(filePath, "utf8");
  for (const entry of entries) {
    const pattern = new RegExp(`^${entry.key}=`, "m");
    if (!pattern.test(content)) {
      return { ok: false, reason: `${entry.key} missing` };
    }
    if (!entry.value) {
      return { ok: false, reason: `${entry.key} empty` };
    }
  }

  return { ok: true };
}

function verifyInfraScriptContract(infraDir) {
  const shPath = path.join(infraDir, "zaloclaw-docker-setup.sh");
  const ps1Path = path.join(infraDir, "zaloclaw-docker-setup.ps1");

  return {
    shExists: fs.existsSync(shPath),
    ps1Exists: fs.existsSync(ps1Path),
    shPath,
    ps1Path,
  };
}

function cleanupOpenClawConfigDir(state, envPath, stepId = "infra") {
  const configDir = readEnvValue(envPath, "OPENCLAW_CONFIG_DIR");
  if (!configDir) {
    throw new Error(`OPENCLAW_CONFIG_DIR is missing in ${envPath}`);
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

async function runInfraScript(state, infraDir) {
  const contract = verifyInfraScriptContract(infraDir);
  if (!contract.shExists || !contract.ps1Exists) {
    addLog(
      state,
      "warn",
      "Infra script contract check failed: both .sh and .ps1 files are expected in zaloclaw-infra."
    );
  }

  if (state.platform.isMac) {
    if (!contract.shExists) {
      return { ok: false, reason: "Missing zaloclaw-docker-setup.sh" };
    }
    const run = await runCommand("bash", [contract.shPath], {
      cwd: infraDir,
      shell: false,
      inheritOutput: true,
      env: {
        ...process.env,
        ZALOC_SETUP_CONTRACT_VERSION: "1",
      },
    });
    return run.code === 0
      ? { ok: true }
      : { ok: false, reason: `Infra script exited with code ${run.code}` };
  }

  if (state.platform.isWindows) {
    if (!contract.ps1Exists) {
      return { ok: false, reason: "Missing zaloclaw-docker-setup.ps1" };
    }
    const run = await runCommand(
      "powershell",
      [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        contract.ps1Path,
      ],
      {
        cwd: infraDir,
        shell: false,
        inheritOutput: true,
        env: {
          ...process.env,
          ZALOC_SETUP_CONTRACT_VERSION: "1",
        },
      }
    );
    return run.code === 0
      ? { ok: true }
      : { ok: false, reason: `Infra script exited with code ${run.code}` };
  }

  return { ok: false, reason: "Unsupported platform. Only macOS and Windows are supported." };
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

async function maybeRunUi(state, rl, uiDir) {
  const runNow = await askYesNo(rl, "Setup complete. Start UI now with docker compose up?", false);
  if (!runNow) {
    state.uiRuntime.status = "skipped";
    state.uiRuntime.lastMessage = "User skipped UI launch";
    return;
  }

  const envPath = path.join(uiDir, ".env");
  if (!fs.existsSync(envPath)) {
    state.uiRuntime.status = "failed";
    state.uiRuntime.lastMessage = "Cannot start UI: .env not found in zaloclaw-ui";
    addLog(state, "warn", state.uiRuntime.lastMessage);
    return;
  }

  addLog(state, "info", "Launching UI with docker compose up --build -d...");
  state.uiRuntime.status = "running";

  const run = await runCommand("docker", ["compose", "up", "--build", "-d"], {
    cwd: uiDir,
    shell: false,
    inheritOutput: true,
    env: {
      ...process.env,
    },
  });

  state.uiRuntime.exitCode = run.code;
  if (run.code === 0) {
    state.uiRuntime.status = "completed";
    state.uiRuntime.lastMessage = "UI docker compose started successfully";
    addLog(state, "info", "zaloclaw-ui is running via docker compose (detached).");
  } else {
    state.uiRuntime.status = "failed";
    state.uiRuntime.lastMessage = `docker compose exited with code ${run.code}`;
  }
}

async function runSetup() {
  const workspaceRoot = process.cwd();
  const platformInfo = await detectPlatformInfo();
  const state = makeState(platformInfo, workspaceRoot);
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  try {
    printHeader(state);

    setStepStatus(state, "platform", "running");
    addCheckpoint(state, "platform", `Detected platform ${platformInfo.name}`);
    addCheckpoint(state, "platform", `Admin-like permissions: ${platformInfo.isAdminLike}`);
    setStepStatus(state, "platform", "done");
    persistState(state);

    setStepStatus(state, "prerequisites", "running");
    let missing = await checkPrerequisites(platformInfo);
    missing = missing.filter((item) => !item.exists);
    if (missing.length > 0) {
      getStep(state, "prerequisites").retries += 1;
      missing = await resolveMissingPrerequisites(state, rl);
    }

    if (missing.length > 0) {
      const reason = `Missing prerequisites after install attempts: ${missing
        .map((item) => item.label)
        .join(", ")}`;
      setStepStatus(state, "prerequisites", "blocked", { error: reason });
      state.blockedReasons.push(reason);
      addLog(state, "error", reason);
      addLog(state, "info", "Setup is blocked. Install the missing tools, then rerun npm run setup.");
      persistState(state);
      return 1;
    }
    setStepStatus(state, "prerequisites", "done");
    addCheckpoint(state, "prerequisites", "All prerequisites available");
    persistState(state);

    setStepStatus(state, "clone", "running");
    const cloneResult = await cloneRepositories(state, rl);
    for (const item of cloneResult.results) {
      addCheckpoint(state, "clone", `${item.repo}: ${item.message}`);
    }
    if (!cloneResult.ok) {
      const reason = "Clone workflow did not complete successfully.";
      setStepStatus(state, "clone", "blocked", { error: reason });
      state.blockedReasons.push(reason);
      persistState(state);
      return 1;
    }
    setStepStatus(state, "clone", "done");
    persistState(state);

    setStepStatus(state, "env", "running");
    const infraDir = path.join(workspaceRoot, "zaloclaw-infra");
    if (!fs.existsSync(infraDir)) {
      const reason = "zaloclaw-infra directory not found after clone step.";
      setStepStatus(state, "env", "failed", { error: reason });
      state.blockedReasons.push(reason);
      persistState(state);
      return 1;
    }

    const envEntries = await collectEnvValues(state, rl, infraDir);
    const envPath = path.join(infraDir, ".env");
    fs.writeFileSync(envPath, serializeEnv(envEntries), "utf8");
    const envVerify = verifyEnvFile(envPath, envEntries);
    if (!envVerify.ok) {
      const reason = `Failed env pre-flight: ${envVerify.reason}`;
      setStepStatus(state, "env", "failed", { error: reason });
      state.blockedReasons.push(reason);
      persistState(state);
      return 1;
    }
    addCheckpoint(state, "env", `Wrote ${envPath}`);

    const gatewayToken = readEnvValue(envPath, "OPENCLAW_GATEWAY_TOKEN");
    const uiDir = path.join(workspaceRoot, "zaloclaw-ui");
    if (fs.existsSync(uiDir) && gatewayToken) {
      addLog(state, "info", "Setting up zaloclaw-ui .env with gateway token...");
      const uiPrePopulated = {
        NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN: gatewayToken,
      };
      const uiEnvEntries = await collectEnvValues(state, rl, uiDir, uiPrePopulated);
      const uiEnvPath = path.join(uiDir, ".env");
      fs.writeFileSync(uiEnvPath, serializeEnv(uiEnvEntries), "utf8");
      const uiEnvVerify = verifyEnvFile(uiEnvPath, uiEnvEntries);
      if (!uiEnvVerify.ok) {
        addLog(state, "warn", `UI env pre-flight failed: ${uiEnvVerify.reason}`);
      } else {
        addCheckpoint(state, "env", `Wrote ${uiEnvPath}`);
      }
    }

    setStepStatus(state, "env", "done");
    persistState(state);

    setStepStatus(state, "infra", "running");
    cleanupOpenClawConfigDir(state, envPath, "infra");
    const infraResult = await runInfraScript(state, infraDir);
    if (!infraResult.ok) {
      const reason = infraResult.reason || "Unknown infra script failure";
      setStepStatus(state, "infra", "failed", { error: reason });
      state.blockedReasons.push(reason);
      persistState(state);
      return 1;
    }
    setStepStatus(state, "infra", "done");
    addCheckpoint(state, "infra", "Infra script completed");
    persistState(state);

    let infraGatewayToken = null;
    let gatewayContainerName = null;

    try {
      infraGatewayToken = readEnvValue(envPath, "OPENCLAW_GATEWAY_TOKEN");
      if (infraGatewayToken) {
        addLog(state, "info", `OpenClaw Gateway Token: ${infraGatewayToken}`);
      }
    } catch (error) {
      addLog(state, "warn", `Could not read gateway token: ${String(error)}`);
    }

    try {
      gatewayContainerName = await findOpenClawGatewayContainer(state);
      if (gatewayContainerName) {
        const uiDir = path.join(workspaceRoot, "zaloclaw-ui");
        if (fs.existsSync(uiDir)) {
          updateUiEnvContainerName(state, uiDir, gatewayContainerName);
        }
      }
    } catch (error) {
      addLog(state, "warn", `Could not update UI container name: ${String(error)}`);
    }

    setStepStatus(state, "ui", "running");

    await maybeRunUi(state, rl, uiDir);
    setStepStatus(state, "ui", "done");
    persistState(state);

    state.setupCompletion.status = "complete";
    state.setupCompletion.completedAt = new Date().toISOString();
    persistState(state);

    addLog(state, "info", "Setup workflow finished.");
    printStepSummary(state, infraGatewayToken);
    return 0;
  } catch (error) {
    addLog(state, "error", `Unexpected setup error: ${String(error)}`);
    state.setupCompletion.status = "failed";
    persistState(state);
    printStepSummary(state);
    return 1;
  } finally {
    rl.close();
  }
}

runSetup().then((code) => {
  process.exitCode = code;
});
