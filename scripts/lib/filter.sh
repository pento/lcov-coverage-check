# Source guard — prevent double-sourcing
[[ -n "${_LIB_FILTER_LOADED:-}" ]] && return 0
_LIB_FILTER_LOADED=1

# should_ignore_file PATH PATTERNS
#   Returns 0 (true) if PATH matches any of the newline-separated glob patterns.
should_ignore_file() {
  local path="$1" patterns="$2"
  [[ -z "$patterns" ]] && return 1
  local pattern
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    # shellcheck disable=SC2254
    if [[ "$path" == $pattern ]]; then
      return 0
    fi
  done <<< "$patterns"
  return 1
}

# filter_lcov_file FILE PATTERNS
#   Creates a filtered copy of an LCOV file, excluding records whose SF: path
#   matches any ignore pattern. Prints the path to the filtered file.
#   If no patterns or the file is empty/missing, prints the original path.
filter_lcov_file() {
  local file="$1" patterns="$2"
  if [[ -z "$patterns" || ! -s "$file" ]]; then
    echo "$file"
    return
  fi
  local filtered
  filtered="$(mktemp "${TMPDIR:-/tmp}/lcov-filtered-XXXXXX")"
  local skip=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == SF:* ]]; then
      if should_ignore_file "${line#SF:}" "$patterns"; then
        skip=true
      else
        skip=false
      fi
    fi
    if [[ "$line" == "end_of_record" && "$skip" == true ]]; then
      skip=false
      continue
    fi
    [[ "$skip" == true ]] && continue
    echo "$line" >> "$filtered"
  done < "$file"
  echo "$filtered"
}
