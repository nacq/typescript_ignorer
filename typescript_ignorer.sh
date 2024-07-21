#!/bin/bash

WD=$(pwd)
OUTPUT_FILE="$WD/output"
TARGET_DIR="$1"
ROOT_DIR="$2"
DEBUG="$3"

if [ $# -eq 0 ] || [ ! -d "$TARGET_DIR" ]; then
    echo -e "Usage: ./typescript_ignorer <directory_to_run_tsc> [root_dir_tsconfig_location]
If no root_dir_tsconfig_location is given it defaults to the value of directory_to_run_tsc"
    exit 1
fi

[[ -f "$OUTPUT_FILE" ]] && rm "$OUTPUT_FILE"

# if no trailing slashes, add them
TARGET_DIR="${TARGET_DIR%/}/"
if [ ! -z "$ROOT_DIR" ]; then
  ROOT_DIR="${ROOT_DIR%/}/"
fi

collect_errors() {
  if [ -z "$ROOT_DIR" ]; then
    command="$TARGET_DIR/node_modules/typescript/bin/tsc"
  else
    command="$ROOT_DIR/node_modules/typescript/bin/tsc"
  fi

  cd "$TARGET_DIR" \
    && eval "$command" --noEmit --project "$TARGET_DIR/tsconfig.json" > "$OUTPUT_FILE" \
    && cd "$WD"
}

# $1 file name
# $2 line number
# get the previous non blank line removing leading white spaces
get_prev_line_with_content() {
  local line_number="$2"
  while [ "$line_number" -gt 0 ]; do
    local line=$(sed -n "${line_number}p" "$1" | sed 's/^[[:space:]]*//')
    if [ ! -z "$line" ]; then
      echo "$line"
      return
    fi
    line_number=$((line_number - 1))
  done
}

touch "$OUTPUT_FILE"

collect_errors

# amount of unique errors by file
error_amount=$(cat "$OUTPUT_FILE" | grep "error TS" | awk -F "(" '{print $1}' | sort | uniq | wc -l | awk '{print $1}')

echo "Found $error_amount errors. Adding comments to ignore them..."

curr_file=""
line_shifts=0
# keep only the lines containing a typescript error, keep the unique lines based on the file path and start looping
# line by line
# NOTE: no need to sort tsc output, it's already sorted by file name and file line
grep "error TS" "$OUTPUT_FILE" | uniq | while IFS= read -r line; do
  file_name=$(echo "$line" | awk -F "(" '{print $1}')

  if [[ "$curr_file" != "$file_name" ]]; then
    curr_file="$file_name"
    line_shifts=0
  fi

  file="$TARGET_DIR$file_name"
  og_line_number=$(echo "$line" | awk -F "(" '{print $2}' | awk -F "," '{print $1}')
  # each comment added adds a line
  line_number=$((og_line_number + line_shifts))
  error_message=$(echo "$line" | awk -F ":" '{print $2$3}')

  # comments inside jsx blocks use a different syntax ("{/* */}") this logic tries to detect if we are dealing with a
  # jsx block and use that instead of "//"
  # check if the line starts with "<" ignoring leading white spaces, to **assume** it's jsx
  trimmed_line=$(head -n "$line_number" "$file_name" | tail -n 1 | sed 's/^[[:space:]]*//')
  comment=$(echo "// @ts-expect-error: TODO FIXME$error_message")

  # if the previous line already has a comment, ignore it
  # NOTE: this makes the comment to be related to the first error caught only
  previous_line=$(sed -n "$((line_number - 1))p" "$file" | sed 's/^[[:space:]]*//')
  if [[ "$previous_line" == "// @ts-expect-error:"* ]] || [[ "$previous_line" == "{/* @ts-expect-error:"* ]]; then
    continue
  fi

  # assuming that if the error is in the first line, it is not a jsx block
  if [[ "$line_number" > 1 ]] && [[ "${file_name##*.}" == "tsx" ]]; then
    trimmed_previous_line=$(get_prev_line_with_content "$file_name" "$((line_number - 1))")
    first_char=${trimmed_line:0:1}
    previous_last_char=${trimmed_previous_line: -1}

    if [[ "$first_char" == "<" ]] && [[ "$previous_last_char" != "(" ]]; then
      comment=$(echo "{/* @ts-expect-error: TODO FIXME$error_message */}")
    elif [[ "$first_char" == "{" ]] && [[ "$previous_last_char" == ">" ]]; then
      comment=$(echo "{/* @ts-expect-error: TODO FIXME$error_message */}")
    elif [[ "$first_char" == "{" ]] && [[ "$previous_last_char" == "}" ]]; then
      comment=$(echo "{/* @ts-expect-error: TODO FIXME$error_message */}")
    elif [[ "$first_char" == "{" ]] && [[ "$previous_last_char" == '"' ]]; then
      comment=$(echo "// @ts-expect-error: TODO FIXME$error_message")
      # to capture an error in the second line of the below snippet
      # ```jsx
      # {arr.map((el: Type) => (
      #   <option value={el.id} key={el.name}>
      # ```
    elif [[ "$first_char" == "<" ]] && [[ "$previous_last_char" == "(" ]]; then
      comment=$(echo "// @ts-expect-error: TODO FIXME$error_message")
    fi
  fi

  # echo -e "File: $file\nLine: $line_number\nComment: $comment\n"
  # write into a copy of the original file the comment and then replace the original with the copy
  awk -v n="$line_number" -v s="$comment" 'NR == n {print s} {print}' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"

  ## DEBUGGING
  if [[ ! -z "$DEBUG" ]]; then
    echo ">>> file $file_name"
    echo ">>> line shifts $line_shifts"
    echo ">>> adding comment on line $line_number"
    echo ">>> original line number $og_line_number"
    echo -e ">>> comment $comment\n"
  fi

  line_shifts=$((line_shifts + 1))
done
