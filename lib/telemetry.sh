# shellcheck shell=bash

function init_telemetry() {
    SERVICE_ID="${1:?Service ID required}"

    RUN_ID="$(generate_uuid)"
    STARTED_AT="$(get_iso8601)"
    START_TIME="$(date +%s)"

    ERROR_LOG="$(mktemp)"
    STATS_FILE="$(mktemp)"
    METRICS_JSON="{}"

    # Default list of exit codes treated as warnings rather than failures
    ALLOWED_WARN_CODES=()

    export SERVICE_ID RUN_ID STARTED_AT START_TIME ERROR_LOG STATS_FILE METRICS_JSON ALLOWED_WARN_CODES

    trap 'cleanup_and_report' EXIT
}

# Helper to mark specific exit codes as non-fatal warnings
function allow_warning_exit_codes() {
    ALLOWED_WARN_CODES=("$@")
}

function cleanup_and_report() {
    local exit_code=$?
    trap - EXIT

    local ended_at end_time duration_seconds status error_msg logs_summary
    ended_at="$(get_iso8601)"
    end_time="$(date +%s)"
    duration_seconds=$(( end_time - START_TIME ))

    status="SUCCESS"
    error_msg=""
    logs_summary=""

    # Check if the exit code is listed in ALLOWED_WARN_CODES
    local is_warning=false
    if [[ "$exit_code" -ne 0 ]]; then
        for code in "${ALLOWED_WARN_CODES[@]}"; do
            if [[ "$exit_code" -eq "$code" ]]; then
                is_warning=true
                break
            fi
        done

        if [[ "$is_warning" == true ]]; then
            status="WARNING"
            error_msg="Completed with warning (non-fatal exit code $exit_code)."
        else
            status="FAILED"
            if [[ -s "${ERROR_LOG:-}" ]]; then
                logs_summary="$(tail -n 10 "$ERROR_LOG" | tr '\n' ' ' | sed 's/"/\\"/g')"
                error_msg="Script terminated with exit code $exit_code. stderr summary: $logs_summary"
            else
                error_msg="Script terminated with exit code $exit_code."
            fi
        fi
    fi

    printf '\n[Telemetry] Run status: %s (Duration: %ss)\n' "$status" "$duration_seconds"
    send_telemetry \
        "${TELEMETRY_URL:-http://telemetry-api:8000}" \
        "$SERVICE_ID" \
        "$RUN_ID" \
        "$status" \
        "$STARTED_AT" \
        "$ended_at" \
        "$duration_seconds" \
        "$METRICS_JSON" \
        "$error_msg" \
        "$logs_summary" || printf 'Warning: Failed to send telemetry.\n' >&2

    rm -f "${ERROR_LOG:-}" "${STATS_FILE:-}"
}

function send_telemetry() {
    # Usage: send_telemetry <endpoint_url> <service_name> <run_id> [status] [started_at] [ended_at] [duration_seconds] [metrics_json] [error_message] [logs_summary]

    if [ "$#" -lt 3 ]; then
        printf 'Error: Missing required arguments.\n' >&2
        printf 'Usage: send_telemetry <endpoint_url> <service_name> <run_id> [status] [started_at] [ended_at] [duration_seconds] [metrics_json] [error_message] [logs_summary]\n' >&2
        return 1
    fi

    local endpoint_url="$1"
    local service_name="$2"
    local run_id="$3"
    local status="${4:-RUNNING}"
    local started_at="${5:-}"
    local ended_at="${6:-}"
    local duration_seconds="${7:-}"
    local metrics_json="${8:-"{}"}"
    local error_message="${9:-}"
    local logs_summary="${10:-}"

    # Default started_at to current UTC time in ISO-8601 format if omitted
    if [ -z "$started_at" ]; then
        started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    fi

    # Validate metrics_json is valid JSON object
    if ! echo "$metrics_json" | jq -e 'if type == "object" then true else false end' >/dev/null 2>&1; then
        printf 'Error: metrics_json must be a valid JSON object string (e.g. '\''{"cpu": 0.5}'\'').\n' >&2
        return 1
    fi

    # Construct payload safely using jq
    local payload
    if ! payload=$(jq -n \
        --arg service_name "$service_name" \
        --arg run_id "$run_id" \
        --arg status "$status" \
        --arg started_at "$started_at" \
        --arg ended_at "$ended_at" \
        --arg duration_seconds "$duration_seconds" \
        --argjson metrics "$metrics_json" \
        --arg error_message "$error_message" \
        --arg logs_summary "$logs_summary" \
        '{
            service_name: $service_name,
            run_id: $run_id,
            status: $status,
            started_at: $started_at,
            ended_at: (if $ended_at == "" then null else $ended_at end),
            duration_seconds: (if $duration_seconds == "" then null else ($duration_seconds | tonumber) end),
            metrics: $metrics,
            error_message: (if $error_message == "" then null else $error_message end),
            logs_summary: (if $logs_summary == "" then null else $logs_summary end)
        }'
    ); then
        printf 'Error: Failed to construct JSON payload.\n' >&2
        return 1
    fi

    # Send payload via curl
    curl --fail --silent --show-error \
        --request POST \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$endpoint_url"
}
