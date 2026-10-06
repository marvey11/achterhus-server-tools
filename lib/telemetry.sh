# shellcheck shell=bash

function init_telemetry() {
    SERVICE_ID="${1:?Service ID required}"

    RUN_ID="${SERVICE_RUN_ID:?SERVICE_RUN_ID must be supplied by the orchestrator}"
    STARTED_AT="$(get_iso8601)"
    START_TIME="$(date +%s)"

    ERROR_LOG="$(mktemp)"
    STATS_FILE="$(mktemp)"
    METRICS_JSON="{}"

    # Default list of exit codes treated as warnings rather than failures
    ALLOWED_WARN_CODES=()

    export SERVICE_ID RUN_ID STARTED_AT START_TIME ERROR_LOG STATS_FILE METRICS_JSON ALLOWED_WARN_CODES

    trap 'cleanup_and_report' EXIT

    report_telemetry_status INITIALIZING ||
        printf 'Warning: Failed to report telemetry initialisation.\n' >&2
}

function start_telemetry() {
    report_telemetry_status RUNNING ||
        printf 'Warning: Failed to report telemetry running status.\n' >&2
}

# Helper to mark specific exit codes as non-fatal warnings
function allow_warning_exit_codes() {
    ALLOWED_WARN_CODES=("$@")
}

function cleanup_and_report() {
    local exit_code="${1:-$?}"
    trap - EXIT

    local status error_msg logs_summary end_time duration_seconds
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
            status="SUCCESS"
            error_msg="Completed with non-fatal exit code $exit_code."
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

    report_telemetry_status "$status" "$error_msg" "$logs_summary" ||
        printf 'Warning: Failed to send telemetry.\n' >&2

    rm -f "${ERROR_LOG:-}" "${STATS_FILE:-}"
}

function report_telemetry_status() {
    # Usage: report_telemetry_status <status> [error_message] [logs_summary]

    if [[ "$#" -lt 1 ]]; then
        printf 'Error: A status is required.\n' >&2
        return 1
    fi

    local status="$1"
    local error_message="${2:-}"
    local logs_summary="${3:-}"
    local endpoint_url="${TELEMETRY_API_URL:-http://telemetry-api:8000}"
    local timestamp payload error_details
    endpoint_url="${endpoint_url%/}/api/v1/runs/${RUN_ID}/status"

    # Validate metrics_json is valid JSON object
    if ! jq -e 'if type == "object" then true else false end' <<<"$METRICS_JSON" >/dev/null 2>&1; then
        printf 'Error: metrics_json must be a valid JSON object string (e.g. '\''{"cpu": 0.5}'\'').\n' >&2
        return 1
    fi

    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    error_details='null'
    if [[ -n "$error_message" ]]; then
        error_details="$(jq -n --arg reason "${status}" --arg message "$error_message" '{reason: $reason, message: $message}')"
    fi

    if ! payload=$(jq -n \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson metrics "$METRICS_JSON" \
        --argjson error_details "$error_details" \
        --arg logs_summary "$logs_summary" \
        '{
            status: $status,
            source: "application",
            timestamp: $timestamp,
            metrics: $metrics,
            error_details: $error_details,
            logs_summary: (if $logs_summary == "" then null else $logs_summary end)
        }'
    ); then
        printf 'Error: Failed to construct JSON payload.\n' >&2
        return 1
    fi

    # Send payload via curl
    curl --fail --silent --show-error \
        --request PATCH \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$endpoint_url"
}
