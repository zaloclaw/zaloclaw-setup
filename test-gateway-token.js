#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");

/**
 * Test script to verify OPENCLAW_GATEWAY_TOKEN transfer from infra .env to UI .env
 */

// Create temporary test directories
const testDir = path.join(os.tmpdir(), "zaloclaw-setup-test");
const infraDir = path.join(testDir, "zaloclaw-infra");
const uiDir = path.join(testDir, "zaloclaw-ui");

console.log("\n=== Testing Gateway Token Transfer ===\n");

// Cleanup and setup
if (fs.existsSync(testDir)) {
  fs.rmSync(testDir, { recursive: true, force: true });
}
fs.mkdirSync(testDir, { recursive: true });
fs.mkdirSync(infraDir, { recursive: true });
fs.mkdirSync(uiDir, { recursive: true });

// Import the functions from setup-cli.js
const setupCliPath = path.join(__dirname, "src", "setup-cli.js");
const setupCliContent = fs.readFileSync(setupCliPath, "utf8");

// Extract readEnvValue function
const readEnvValueMatch = setupCliContent.match(
  /function readEnvValue\(filePath, key\) \{[\s\S]*?\n\}/
);
if (!readEnvValueMatch) {
  console.error("ERROR: Could not extract readEnvValue function");
  process.exit(1);
}

// Extract serializeEnv function
const serializeEnvMatch = setupCliContent.match(
  /function serializeEnv\(entries\) \{[\s\S]*?\n\}/
);
if (!serializeEnvMatch) {
  console.error("ERROR: Could not extract serializeEnv function");
  process.exit(1);
}

// Create a test environment
eval(readEnvValueMatch[0]);
eval(serializeEnvMatch[0]);

// Test 1: Create infra .env with gateway token
console.log("Test 1: Creating infra .env with OPENCLAW_GATEWAY_TOKEN");
const testToken = "test-gateway-token-12345";
const infraEnvContent = `OPENCLAW_API_URL=https://api.example.com
OPENCLAW_API_KEY=test-api-key
OPENCLAW_ENVIRONMENT=development
OPENCLAW_GATEWAY_TOKEN=${testToken}
`;

const infraEnvPath = path.join(infraDir, ".env");
fs.writeFileSync(infraEnvPath, infraEnvContent, "utf8");
console.log(`✓ Created ${infraEnvPath}`);
console.log(`  Content:\n${infraEnvContent}`);

// Test 2: Read the gateway token
console.log("\nTest 2: Reading OPENCLAW_GATEWAY_TOKEN from infra .env");
const readToken = readEnvValue(infraEnvPath, "OPENCLAW_GATEWAY_TOKEN");
console.log(`read value: "${readToken}"`);
if (readToken === testToken) {
  console.log(`✓ Token successfully read: ${readToken}`);
} else {
  console.error(`✗ ERROR: Token mismatch. Expected "${testToken}", got "${readToken}"`);
  process.exit(1);
}

// Test 3: Serialize env entries with pre-populated value
console.log("\nTest 3: Testing serializeEnv with pre-populated values");
const uiEnvEntries = [
  { key: "NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN", value: readToken },
  { key: "NEXT_PUBLIC_API_URL", value: "https://ui.example.com" },
];

const serialized = serializeEnv(uiEnvEntries);
console.log(`✓ Serialized UI env entries:\n${serialized}`);

// Test 4: Write UI .env
console.log("Test 4: Writing UI .env");
const uiEnvPath = path.join(uiDir, ".env");
fs.writeFileSync(uiEnvPath, serialized, "utf8");
console.log(`✓ Created ${uiEnvPath}`);

// Test 5: Verify UI .env contains the token
console.log("\nTest 5: Verifying NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN in UI .env");
const uiEnvContent = fs.readFileSync(uiEnvPath, "utf8");
console.log(`  Content:\n${uiEnvContent}`);

const tokenInUiEnv = readEnvValue(uiEnvPath, "NEXT_PUBLIC_OPENCLAW_GATEWAY_TOKEN");
if (tokenInUiEnv === testToken) {
  console.log(`✓ Token successfully transferred to UI .env: ${tokenInUiEnv}`);
} else {
  console.error(`✗ ERROR: Token not found in UI .env. Expected "${testToken}", got "${tokenInUiEnv}"`);
  process.exit(1);
}

// Test 6: Test with quoted values
console.log("\nTest 6: Testing with quoted values");
const quotedInfraEnv = `OPENCLAW_GATEWAY_TOKEN="quoted-token-value"
OPENCLAW_API_KEY='single-quoted-key'
`;
const quotedInfraPath = path.join(infraDir, ".env.quoted");
fs.writeFileSync(quotedInfraPath, quotedInfraEnv, "utf8");

const quotedToken = readEnvValue(quotedInfraPath, "OPENCLAW_GATEWAY_TOKEN");
const quotedKey = readEnvValue(quotedInfraPath, "OPENCLAW_API_KEY");

console.log(`  Double-quoted value: "${quotedToken}"`);
console.log(`  Single-quoted value: "${quotedKey}"`);

if (quotedToken === "quoted-token-value" && quotedKey === "single-quoted-key") {
  console.log("✓ Quoted values correctly unquoted");
} else {
  console.error("✗ ERROR: Quoted value handling failed");
  process.exit(1);
}

// Cleanup
console.log("\nCleaning up test directories...");
fs.rmSync(testDir, { recursive: true, force: true });
console.log("✓ Test directories removed");

console.log("\n=== All Tests Passed! ===\n");
console.log("Summary:");
console.log("  ✓ Token read from infra .env");
console.log("  ✓ Token serialized to UI .env");
  console.log("  ✓ Token verified in UI .env");
console.log("  ✓ Quoted values handled correctly");
console.log("\nThe gateway token transfer functionality is working correctly.\n");
