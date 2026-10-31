# Achterhus Server Tools

A collection of `bash` service utilities created for the `achterhus` home server.

The Docker image packages executable workers from `app/services`; `app/entrypoint.sh`
dispatches the requested worker by name. Shared shell and telemetry functions
live in `lib/`. The Service Orchestrator supplies each worker's arguments and
`SERVICE_RUN_ID`; scheduling and execution order remain external to this image.

## Telemetry configuration

The storage backup, home files backup, PostgreSQL backup, Google Drive sync and
local Git snapshot services report lifecycle changes to the Achterhus Telemetry
API. Configure these environment variables in the service definition:

| Variable | Required | Description |
| --- | --- | --- |
| `SERVICE_RUN_ID` | Yes | UUID registered for this run by the Service Orchestrator. The service uses this value and does not create or register a run of its own. |
| `TELEMETRY_API_URL` | No | Telemetry API base URL, for example `http://telemetry-api:8000`. Defaults to that value. The API path is appended by the telemetry helper. |

The service name is set by each utility (`backup-storage`, `backup-home-files`,
`backup-postgres`, `sync-gdrive`, `create-git-local-snapshots` or
`apply-git-local-retention`) and must match the name used when the orchestrator
registers the run. The utilities report `INITIALIZING`, then `RUNNING` after
local configuration checks, and finish with `SUCCESS` or `FAILED`. Non-fatal
exit codes configured by a utility are reported as `SUCCESS`.

Status updates use `PATCH /api/v1/runs/{SERVICE_RUN_ID}/status` with
`source: "application"`, a UTC ISO 8601 timestamp, and the current metrics object.
Failed runs include structured `error_details` with a reason and message; available
log summaries and the run duration are included when present. The orchestrator is
responsible for registering the run before starting the container.

## Home directory file backups

Run `backup-home-files` with `--source <dir> --destination <dir> --files-from <file>`
to copy the listed paths from the source home directory. The files-from list
contains paths relative to the source directory, one per line. The source and
destination must be mounted directories, and the destination must be writable.
The service reports the number of files transferred as the `files_backed_up`
telemetry metric.

## PostgreSQL backups

Run `backup-postgres` with `--destination <dir>` to create compressed SQL dumps
of the configured database and PostgreSQL globals. The service expects
`POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB`; `DATABASE_HOST` and
`DATABASE_PORT` are optional and default to `postgres` and `5432`. It reports
the compressed database, globals and combined backup sizes in bytes as telemetry
metrics. The destination directory must already exist and be writable.

## Local Git repository snapshots

Run `create-git-local-snapshots` with `--source <dir> --destination <dir>` to
snapshot the complete source tree, including Git metadata and uncommitted and
untracked files. It creates a timestamped directory and updates the `current`
symlink only after rsync completes. Unchanged files are hard-linked to the
previous snapshot to reduce storage use.

Run `apply-git-local-retention` with `--snapshot-directory <dir>` to retain all
snapshots from the last four weeks, the newest available snapshot in each
calendar month from four weeks through twelve months old, and no older
snapshots. The snapshot referenced by `current` is always retained. Only
completed timestamped snapshot directories are considered.

The external Service Orchestrator must pass the same snapshot-root environment
value as `--destination` to the creation worker and `--snapshot-directory` to
the retention worker. The workers do not read a separate snapshot-root
environment variable.

## Other workers

`backup-storage` mirrors a mounted storage directory to a mounted backup drive
and preserves hard links. `backup-home-files` copies paths from a supplied
files-from list, `backup-postgres` writes compressed database and globals
dumps, and `sync-gdrive` moves files to a configured Google Drive remote. Each
worker has its own CLI help and reports lifecycle status through `lib/telemetry.sh`.
