#!/bin/bash

WD=$(pwd)
OUTPUT_FILE="$WD/output"
TARGET_DIR="$1"

if [ $# -eq 0 ] || [ ! -d "$TARGET_DIR" ]; then
    echo "Usage: ./typescript_ignorer <directory_to_run_tsc>"
    exit 1
fi

[[ -f "$OUTPUT_FILE" ]] && rm "$OUTPUT_FILE"

collect_errors() {
  cd "$TARGET_DIR" \
    && ./node_modules/typescript/bin/tsc > "$OUTPUT_FILE" \
    && cd "$WD"
}

touch "$OUTPUT_FILE"

while true; do
  collect_errors

  # amount of unique errors by file
  error_amount=$(cat "$OUTPUT_FILE" | grep "error TS" | awk -F "(" '{print $1}' | sort | uniq | wc -l)

  [[ "$error_amount" -eq  0 ]] && break

  echo "Found $error_amount. Adding comments to ignore them..."

  # keep only the lines containing a typescript error, keep the unique lines based on the file path and start looping
  # line by line
  cat "$OUTPUT_FILE" | grep "error TS" | awk -F "(" '!seen[$1]++' | sort | uniq | while IFS= read -r line; do
    file_name=$(echo "$line" | awk -F "(" '{print $1}')
    file="$TARGET_DIR$file_name"
    line_number=$(echo "$line" | awk -F "(" '{print $2}' | awk -F "," '{print $1}')
    error_message=$(echo "$line" | awk -F ":" '{print $2$3}')
    comment=$(echo "// @ts-expect-error: TODO FIXME$error_message")

    # echo -e "File: $file\nLine: $line_number\nComment: $comment\n"
    # write into a copy of the original file the comment and then replace the original with the copy
    awk -v n="$line_number" -v s="$comment" 'NR == n {print s} {print}' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  done
done
