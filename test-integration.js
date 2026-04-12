#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const readline = require("readline/promises");

/**
 * Integration test: Simulates the full setup workflow
 */

console.log("\n=== Full Setup Workflow Integration Test ===\n");

// Create test environment
const testDir = path.join(os.tmpdir(), "zaloclaw-integration-test");
const infraDir = path.join(testDir, "zaloclaw-infra");
const uiDir = path.join(testDir, "zaloclaw-ui");

if (fs.existsSync(testDir)) {
  fs.rmSync(testDir, { recursive: true, force: true });
}
fs.mkdirSync(testDir, { recursive: true });
fs.mkdirSync(infraDir, { recursive: true });
fs.mkdirSync(uiDir, { recursive: true });

// Setup template files
console.log("Setting up test environment...");

// Infra .env.example
const infraTemplate = `# Infra Configuration
OPENCLAW_API_URL=https://api.openclaw.io
OPENCLAW_API_KEY=<your-api-key>
OPENCLAW_ENVIRONMENT=production
OPENCLAW_GATEWAY_TOKEN=<your-gateway-token>
`;

fs.writeFileSync(path.join(infraDir, ".env.example"), infraTemplate, "utf8");
console.log("✓ Created infra .env.example");

// UI .env.example
const uiTemplate = `# UI Configuration
NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN=<gateway-token-from-infra>
NEXT_PUBLIC_API_URL=https://api.openclaw.io
NEXT_PUBLIC_ENVIRONMENT=production
`;

fs.writeFileSync(path.join(uiDir, ".env.example"), uiTemplate, "utf8");
console.log("✓ Created UI .env.example");

// Simulate the setup workflow
console.log("\nSimulating setup workflow...\n");

// Extract functions from setup-cli.js
const setupCliPath = path.join(__dirname, "src", "setup-cli.js");
const setupCliContent = fs.readFileSync(setupCliPath, "utf8");

// Get relevant functions
const parseEnvTemplateMatch = setupCliContent.match(
  /function parseEnvTemplate\(templateContent\) \{[\s\S]*?\n\}/
);
const readEnvValueMatch = setupCliContent.match(
  /function readEnvValue\(filePath, key\) \{[\s\S]*?\n\}/
);
const serializeEnvMatch = setupCliContent.match(
  /function serializeEnv\(entries\) \{[\s\S]*?\n\}/
);
const verifyEnvFileMatch = setupCliContent.match(
  /function verifyEnvFile\(filePath, entries\) \{[\s\S]*?\n\}/
);

if (!parseEnvTemplateMatch || !readEnvValueMatch || !serializeEnvMatch || !verifyEnvFileMatch) {
  console.error("ERROR: Could not extract required functions");
  process.exit(1);
}

// Evaluate functions
eval(parseEnvTemplateMatch[0]);
eval(readEnvValueMatch[0]);
eval(serializeEnvMatch[0]);
eval(verifyEnvFileMatch[0]);

// Step 1: Parse infra template and simulate env collection
console.log("Step 1: Collecting infra environment variables");
const infraFields = parseEnvTemplate(infraTemplate);
console.log(`  Found ${infraFields.length} fields: ${infraFields.map((f) => f.key).join(", ")}`);

const infraEntries = infraFields.map((field) => ({
  key: field.key,
  value:
    field.key === "OPENCLAW_GATEWAY_TOKEN"
      ? "gw-token-prod-abc123xyz"
      : field.key === "OPENCLAW_API_KEY"
        ? "sk-prod-def456uvw"
        : field.defaultValue || `value-for-${field.key}`,
}));

console.log("  Infra values to write:");
infraEntries.forEach((e) => console.log(`    ${e.key}=${e.value}`));

// Step 2: Write infra .env
console.log("\nStep 2: Writing infra .env");
const infraEnvPath = path.join(infraDir, ".env");
fs.writeFileSync(infraEnvPath, serializeEnv(infraEntries), "utf8");
const infraVerify = verifyEnvFile(infraEnvPath, infraEntries);
console.log(`✓ Infra .env written: ${infraVerify.ok ? "verified" : "FAILED"}`);

if (!infraVerify.ok) {
  console.error(`  Verification failed: ${infraVerify.reason}`);
  process.exit(1);
}

// Step 3: Extract gateway token
console.log("\nStep 3: Extracting OPENCLAW_GATEWAY_TOKEN");
const gatewayToken = readEnvValue(infraEnvPath, "OPENCLAW_GATEWAY_TOKEN");
console.log(`✓ Gateway token extracted: ${gatewayToken}`);

if (!gatewayToken) {
  console.error("  ERROR: Gateway token not found!");
  process.exit(1);
}

// Step 4: Prepare UI env with pre-populated token
console.log("\nStep 4: Collecting UI environment variables with pre-populated gateway token");
const uiFields = parseEnvTemplate(uiTemplate);
console.log(`  Found ${uiFields.length} fields: ${uiFields.map((f) => f.key).join(", ")}`);

// Simulate pre-population
const prePopulated = { NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN: gatewayToken };

const uiEntries = uiFields.map((field) => {
  const prepopulatedValue = prePopulated[field.key];
  return {
    key: field.key,
    value:
      prepopulatedValue ||
      (field.key === "NEXT_PUBLIC_API_URL"
        ? "https://api.openclaw.io"
        : field.defaultValue || `value-for-${field.key}`),
  };
});

console.log("  UI values to write:");
uiEntries.forEach((e) => {
  const source = prePopulated[e.key] ? " (from infra)" : "";
  console.log(`    ${e.key}=${e.value}${source}`);
});

// Step 5: Write UI .env
console.log("\nStep 5: Writing UI .env");
const uiEnvPath = path.join(uiDir, ".env");
fs.writeFileSync(uiEnvPath, serializeEnv(uiEntries), "utf8");
const uiVerify = verifyEnvFile(uiEnvPath, uiEntries);
console.log(`✓ UI .env written: ${uiVerify.ok ? "verified" : "FAILED"}`);

if (!uiVerify.ok) {
  console.error(`  Verification failed: ${uiVerify.reason}`);
  process.exit(1);
}

// Step 6: Verify token transfer
console.log("\nStep 6: Verifying token transfer");
const uiTokenValue = readEnvValue(uiEnvPath, "NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN");
console.log(`✓ UI token value: ${uiTokenValue}`);

if (uiTokenValue !== gatewayToken) {
  console.error(`ERROR: Token mismatch! Infra: ${gatewayToken}, UI: ${uiTokenValue}`);
  process.exit(1);
}

// Show final files
console.log("\n=== Final Configuration Files ===\n");
console.log("Infra .env:");
console.log(fs.readFileSync(infraEnvPath, "utf8"));
console.log("UI .env:");
console.log(fs.readFileSync(uiEnvPath, "utf8"));

// Cleanup
fs.rmSync(testDir, { recursive: true, force: true });

console.log("=== Integration Test Passed! ===\n");
console.log("✓ Infra .env collected and written");
console.log("✓ Gateway token extracted from infra .env");
console.log(
  "✓ UI .env prepared with NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN pre-populated"
);
console.log("✓ Token value verified in UI .env\n");
