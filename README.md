# Achterhus Server Tools

A collection of `bash` service utilities created for the `achterhus` home server.

## Telemetry configuration

The backup and Google Drive sync services report lifecycle changes to the Achterhus
Telemetry API. Configure these environment variables in the service definition:

| Variable | Required | Description |
| --- | --- | --- |
| `SERVICE_RUN_ID` | Yes | UUID registered for this run by the Service Orchestrator. The service uses this value and does not create or register a run of its own. |
| `TELEMETRY_API_URL` | No | Telemetry API base URL, for example `http://telemetry-api:8000`. Defaults to that value. The API path is appended by the telemetry helper. |

The service name is set by each utility (`backup-storage` or `sync-gdrive`) and
must match the name used when the orchestrator registers the run. The utilities
report `INITIALIZING`, then `RUNNING` after local configuration checks, and finish
with `SUCCESS` or `FAILED`. Non-fatal exit codes configured by a utility are
reported as `SUCCESS`.

Status updates use `PATCH /api/v1/runs/{SERVICE_RUN_ID}/status` with
`source: "application"`, a UTC ISO 8601 timestamp, and the current metrics object.
Failed runs include structured `error_details` with a reason and message; available
log summaries and the run duration are included when present. The orchestrator is
responsible for registering the run before starting the container.
