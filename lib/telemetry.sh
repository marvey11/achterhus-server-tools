# shellcheck shell=bash

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
