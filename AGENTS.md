# Repository guidance

- Implement shell utilities for Bash with `set -euo pipefail` compatible behaviour.
- Keep shell code clean under strict ShellCheck checks.
- Run the configured ShellCheck pre-commit hook with
  `uvx pre-commit run shellcheck --files <script>`.
- Use British or International English in documentation and user-facing text.
- Telemetry run IDs are supplied by the Service Orchestrator in `SERVICE_RUN_ID`;
  services must not generate or register replacement runs.
- Follow the Telemetry API contract documented in
  `../achterhus-documentation/docs/achterhus_telemetry.md` when changing reports.
- Keep credentials and other secrets out of source files and checked-in examples.
- Service workers live in `app/services`; the entrypoint discovers executable
  scripts there by filename. The shared shell helpers live in `lib`.
- Keep service scripts compatible with the Alpine-based Docker image. Add
  required runtime packages to `Dockerfile` only when a new dependency is needed.
- Run repository quality checks with `uvx pre-commit run --all-files`; for a
  focused ShellCheck run use `uvx pre-commit run shellcheck --files <script>`.
- The Docker image build in `.github/workflows/ci.yaml` validates packaging.
- Snapshot workers accept their directories as CLI options. The external
  orchestrator maps its shared snapshot-root environment variable to both
  workers and supplies each run's `SERVICE_RUN_ID`.
