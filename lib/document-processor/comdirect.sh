# shellcheck shell=bash

function process_comdirect() {
    local file="$1"

    local filename
    filename=$(basename "$file")

    local COMDIRECT_BASE="${DOCUMENT_STORAGE}/finances/comdirect"

    case "$filename" in
        # 1. Monthly Financial Reports
        Finanzreport_*.pdf)
            if [[ $filename =~ Finanzreport_Nr\._([0-9]{2})_per_([0-9]{2})\.([0-9]{2})\.([0-9]{4})_.*\.pdf$ ]]; then
                report_nr="${BASH_REMATCH[1]}"
                day="${BASH_REMATCH[2]}"
                month="${BASH_REMATCH[3]}"
                year="${BASH_REMATCH[4]}"

                iso_date="${year}-${month}-${day}"
                target_dir="${COMDIRECT_BASE}/statements/$year"
                target_name="${iso_date}_Finanzreport_Nr_${report_nr}.pdf"

                move_and_verify "$file" "$target_dir" "$target_name"
                return $?
            fi

            # If we reach here, it means we failed to process the file
            return 1
            ;;

        # 2. Securities Documents
        Buchungsanzeige* | Dividendengutschrift* | Erträgnisgutschrift* | Wertpapierabrechnung* | Steuermitteilung*)
            # --- NORMALISATION ---
            clean="${file//_WKN_/_}"
            clean=$(echo "$clean" | sed -E 's/([A-Z0-9]{6})\(/\1_(/g')

            # --- EXTRACTION ---
            if [[ "$clean" =~ _vom_([0-9]{2})\.([0-9]{2})\.([0-9]{4}) ]]; then
                day="${BASH_REMATCH[1]}"
                month="${BASH_REMATCH[2]}"
                year="${BASH_REMATCH[3]}"
                iso_date="${year}-${month}-${day}"

                # Now find the WKN independently
                if [[ "$clean" =~ ([A-Z0-9]{6}) ]]; then
                    wkn="${BASH_REMATCH[1]}"

                    target_dir="${COMDIRECT_BASE}/securities/$year/$wkn"
                    target_name="${iso_date}_${filename}"

                    move_and_verify "$file" "$target_dir" "$target_name"
                    return $?
                fi
            else
                echo "WARN: Transaction pattern match failed for '$file'"
                return 1
            fi

            # If we reach here, it means we failed to process the file
            return 1
            ;;

        # 3. Catch-all for everything else
        *)
            echo "Skipping unknown file type: $file"
            return 1
            ;;
    esac
}
