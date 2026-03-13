# shellcheck shell=bash

function process_ryd() {
    local file="$1"
    local filename
    local target_dir

    filename=$(basename "$file")
    target_dir="${DOCUMENT_STORAGE}/auto/ryd"

    # --- Date Extraction ---
    # Looks for "Rechnungsdatum: DD.MM.YYYY" on the first page of the PDF
    raw_date=$(pdfgrep -oP '(?<=Rechnungsdatum:)\s+\K\d{2}\.\d{2}\.\d{4}' "$file")

    if [ -n "$raw_date" ]; then
        day="${raw_date:0:2}"
        month="${raw_date:3:2}"
        year="${raw_date:6:4}"
        iso_date=$(date -d "${year}-${month}-${day}" +%Y-%m-%d)

        target_name="${iso_date}_${filename}"

        move_and_verify "$file" "$target_dir" "$target_name"
        return $?
    else
        echo "[$(date)] WARNING: No invoice date detected in $file"
        return 1
    fi
}
