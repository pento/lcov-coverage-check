# Source guard — prevent double-sourcing
[[ -n "${_LIB_COMMON_LOADED:-}" ]] && return 0
_LIB_COMMON_LOADED=1

# write_output KEY VALUE — append to $GITHUB_OUTPUT if available
write_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

# append_summary TEXT — append markdown to $GITHUB_STEP_SUMMARY if available
append_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >> "$GITHUB_STEP_SUMMARY"
  fi
}

# _escape_annotation_data TEXT — escape message data for a workflow command
# (rules from @actions/core: % \r \n)
_escape_annotation_data() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//$'\r'/%0D}"
  s="${s//$'\n'/%0A}"
  printf '%s' "$s"
}

# _escape_annotation_property TEXT — escape a property value (data rules plus : and ,)
_escape_annotation_property() {
  local s
  s="$(_escape_annotation_data "$1")"
  s="${s//:/%3A}"
  s="${s//,/%2C}"
  printf '%s' "$s"
}

# build_annotation_title LABEL — "Coverage", or "Coverage (LABEL)" when LABEL is non-empty
build_annotation_title() {
  printf 'Coverage%s' "${1:+ ($1)}"
}

# emit_annotation LEVEL TITLE MESSAGE [FILE] — print a ::error/::warning/::notice
# workflow command so the runner creates an annotation. When FILE is given,
# line=1 is added so the annotation is file-level and renders in the PR diff.
emit_annotation() {
  local level="$1" title="$2" message="$3" file="${4:-}"
  local props
  props="title=$(_escape_annotation_property "$title")"
  if [[ -n "$file" ]]; then
    props="file=$(_escape_annotation_property "$file"),line=1,${props}"
  fi
  echo "::${level} ${props}::$(_escape_annotation_data "$message")"
}

# begin_group TITLE — open a collapsible group in the Actions log viewer
begin_group() {
  echo "::group::$(_escape_annotation_data "$1")"
}

# end_group — close the group opened by begin_group
end_group() {
  echo "::endgroup::"
}
