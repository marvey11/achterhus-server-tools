# Repository guidance

- Implement shell utilities for Bash with `set -euo pipefail` compatible behaviour.
- Keep shell code clean under strict ShellCheck checks.
- Use British or International English in documentation and user-facing text.
- Telemetry run IDs are supplied by the Service Orchestrator in `SERVICE_RUN_ID`;
  services must not generate or register replacement runs.
- Follow the Telemetry API contract documented in
  `../achterhus-documentation/docs/achterhus_telemetry.md` when changing reports.
- Keep credentials and other secrets out of source files and checked-in examples.
