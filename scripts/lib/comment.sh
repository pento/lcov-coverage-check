# Source guard — prevent double-sourcing
[[ -n "${_LIB_COMMENT_LOADED:-}" ]] && return 0
_LIB_COMMENT_LOADED=1

# build_section KEY SOURCE_ID CONTENT
#   Wraps CONTENT in section delimiters with an embedded source tag.
#   CONTENT should contain actual newlines (not literal \n sequences).
#   Output is written to stdout with actual newlines.
build_section() {
  local key="$1" source_id="$2" content="$3"
  printf '%s\n%s\n%s\n%s\n' \
    "<!-- lcov-section:${key} -->" \
    "<!-- lcov-section-source:${source_id} -->" \
    "$content" \
    "<!-- lcov-section-end:${key} -->"
}

# extract_section_keys BODY
#   Prints newline-separated section keys found in BODY.
extract_section_keys() {
  local body="$1"
  echo "$body" | grep -o '<!-- lcov-section:[^ ]*' | sed 's/<!-- lcov-section://' || true
}

# replace_section BODY KEY NEW_SECTION
#   Replaces the section for KEY in BODY (or appends it if absent).
#   Returns the rebuilt comment: top-level marker, then sections sorted
#   with "default" first and the rest alphabetical.
#   All inputs/outputs use actual newlines (not literal \n).
replace_section() {
  local body="$1" key="$2" new_section="$3"

  # Collect all existing section keys
  local existing_keys
  existing_keys="$(extract_section_keys "$body")"

  # Build a temporary directory to hold sections; clean up on any exit path
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-sections-XXXXXX")"

  # Extract each existing section (except the one we're replacing) into files.
  # Uses index() for matching to tolerate trailing whitespace on marker lines.
  if [[ -n "$existing_keys" ]]; then
    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      if [[ "$k" == "$key" ]]; then
        continue  # skip — we'll use the new section instead
      fi
      echo "$body" | awk -v start="<!-- lcov-section:${k} -->" \
                          -v end="<!-- lcov-section-end:${k} -->" '
        index($0, start) == 1 { found=1 }
        found { print }
        index($0, end) == 1 { found=0 }
      ' > "${tmpdir}/${k}"
    done <<< "$existing_keys"
  fi

  # Write the new/replacement section
  printf '%s\n' "$new_section" > "${tmpdir}/${key}"

  # Sort keys: "default" first, then alphabetical
  local sorted_keys
  sorted_keys="$( {
    ls "$tmpdir" | grep -x 'default' || true
    ls "$tmpdir" | grep -vx 'default' | sort
  } )"

  # Rebuild comment
  local result="<!-- lcov-coverage-check -->"
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    result+=$'\n'"$(cat "${tmpdir}/${k}")"
  done <<< "$sorted_keys"

  rm -rf "$tmpdir"
  echo "$result"
}
