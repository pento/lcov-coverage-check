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
