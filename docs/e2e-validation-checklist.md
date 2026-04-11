# End-to-End Validation Checklist

Use this checklist on clean machines for both macOS and Windows.

## Pre-check

- Machine has internet access.
- No existing `zaloclaw-ui` or `zaloclaw-infra` folders in target workspace.
- Setup package is launched from an empty workspace root.

## Workflow Validation

- Start setup with `npm run setup`.
- Confirm platform detection reports correct OS and permission context.
- Confirm prerequisite step checks Docker Desktop, Git, Node.js, and npm.
- For a missing tool, confirm installer guidance appears and re-validation runs after install attempt.
- Confirm blocked-state message appears if prerequisites remain missing.
- Confirm repository step clones both repositories to exact folders:
  - `zaloclaw-ui`
  - `zaloclaw-infra`
- Confirm conflict flow supports `reuse`, `replace`, and `cancel` decisions.
- Confirm `.env` wizard validates required values and prevents continuation on empty required fields.
- Confirm `zaloclaw-infra/.env` is created and passes pre-flight verification.
- Confirm infra script execution is OS-specific:
  - macOS: `zaloclaw-docker-setup.sh`
  - Windows: `zaloclaw-docker-setup.ps1`
- Confirm optional UI step allows user to skip or run `npm run dev`.
- Confirm setup summary differentiates setup completion from UI runtime status.
- Confirm `setup-state.json` is generated with step checkpoints and errors.

## Failure Scenarios

- Simulate unavailable Git and verify blocked-state UX.
- Force clone failure (invalid network) and verify retry prompt for failed repos.
- Provide invalid required env values and verify wizard blocks progression.
- Force infra script non-zero exit and verify setup reports failure reason.

## Exit Criteria

- All workflow checks pass on macOS.
- All workflow checks pass on Windows.
- Failure scenarios produce clear, actionable errors and state snapshots.
