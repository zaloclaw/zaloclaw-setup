# Infra Script Alignment Checklist

Use this checklist to keep `zaloclaw-docker-setup.sh` and `zaloclaw-docker-setup.ps1` aligned.

## Behavior Checklist

- Both scripts can be started from `zaloclaw-infra` root.
- Both scripts fail fast when Docker is unavailable.
- Both scripts validate required `.env` values before provisioning actions.
- Both scripts print user-actionable error messages.
- Both scripts return exit code `0` for success.
- Both scripts return non-zero exit code for failures.
- Both scripts emit a start banner including contract version `1`.

## Error Contract

- Missing prerequisites: exit `2`.
- Invalid or missing `.env` values: exit `3`.
- Provisioning/runtime failure: exit `4`.
- Unknown/unhandled error: exit `10`.

## Validation Process

1. Run script on clean macOS machine.
2. Run script on clean Windows machine.
3. Capture stdout/stderr and exit codes.
4. Verify behavior parity against this checklist.
