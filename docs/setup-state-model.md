# Setup State Model

The setup package stores runtime state in `setup-state.json` at the workspace root.

## Top-level Fields

- `startedAt`: ISO timestamp when setup started.
- `platform`: detected platform and permission context.
- `workspaceRoot`: root where `zaloclaw-ui` and `zaloclaw-infra` are created.
- `logs`: chronological event stream with level prefixes.
- `blockedReasons`: reasons that prevent setup from continuing.
- `steps`: ordered step list with status and checkpoints.
- `setupCompletion`: overall setup completion status.
- `uiRuntime`: optional UI launch runtime status.

## Step Object Shape

Each step in `steps` contains:

- `id`: stable step identifier (`platform`, `prerequisites`, `clone`, `env`, `infra`, `ui`).
- `title`: user-facing title.
- `status`: one of `pending`, `running`, `done`, `failed`, `blocked`.
- `retries`: retry counter for re-attempted operations.
- `checkpoints`: timestamped milestones captured while running a step.
- `lastError`: latest error message if the step failed or blocked.
- `startedAt`: step start timestamp.
- `endedAt`: step completion timestamp.

## Completion and Runtime Fields

- `setupCompletion.status`: `pending`, `complete`, or `failed`.
- `setupCompletion.completedAt`: completion timestamp when status is `complete`.
- `uiRuntime.status`: `not-started`, `running`, `completed`, `failed`, or `skipped`.
- `uiRuntime.pid`: process ID when available.
- `uiRuntime.exitCode`: process exit code for completed/failed runs.
- `uiRuntime.lastMessage`: latest runtime note for UI launch.

## Usage

- The CLI updates state after each step transition.
- Failures and blocked states are persisted before process exit.
- Users can inspect `setup-state.json` for diagnostics and retry context.
