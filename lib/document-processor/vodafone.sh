# shellcheck shell=bash

function process_vodafone() {
    local file="$1"
    local filename

    filename=$(basename "$file")

    # Pattern: YYYY-MM-DD_Rechnung_Kundennr_119518058.pdf
    if [[ $filename =~ ^([0-9]{4})-[0-9]{2}-[0-9]{2}_Rechnung.* ]]; then
        year="${BASH_REMATCH[1]}"

        move_and_verify "$file" "${DOCUMENT_STORAGE}/telecom/vodafone.com/$year" "$filename"
        return $?
    fi

    # If we reach here, it means we failed to process the file
    return 1
}
