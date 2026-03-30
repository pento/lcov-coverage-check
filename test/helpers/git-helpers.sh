# ---------------------------------------------------------------------------
# Helper: create a temp git repo with baseline and head commits
# Returns the temp dir path. Sets GIT_BASE_REF and GIT_HEAD_REF.
# Args:
#   $1 - associative: "base" files (space-separated "path:content" pairs)
#   $2 - associative: "head" files to add (space-separated "path:content" pairs)
#   $3 - associative: "head" files to modify (space-separated "path:content" pairs)
# ---------------------------------------------------------------------------
setup_git_repo() {
  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/lcov-test-XXXXXX")"

  (
    cd "$tmpdir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Base commit with files
    local base_files="$1"
    if [[ -n "$base_files" ]]; then
      for entry in $base_files; do
        local fpath="${entry%%:*}"
        local fcontent="${entry#*:}"
        mkdir -p "$(dirname "$fpath")"
        echo "$fcontent" > "$fpath"
        git add "$fpath"
      done
    fi
    git commit -q --allow-empty -m "base commit"
    git tag base_ref

    # Head commit: add new files
    local new_files="${2:-}"
    if [[ -n "$new_files" ]]; then
      for entry in $new_files; do
        local fpath="${entry%%:*}"
        local fcontent="${entry#*:}"
        mkdir -p "$(dirname "$fpath")"
        echo "$fcontent" > "$fpath"
        git add "$fpath"
      done
    fi

    # Head commit: modify existing files
    local mod_files="${3:-}"
    if [[ -n "$mod_files" ]]; then
      for entry in $mod_files; do
        local fpath="${entry%%:*}"
        local fcontent="${entry#*:}"
        echo "$fcontent" > "$fpath"
        git add "$fpath"
      done
    fi

    git commit -q --allow-empty -m "head commit"
    git tag head_ref
  )

  echo "$tmpdir"
}

cleanup_git_repo() {
  if [[ -n "${1:-}" && -d "$1" ]]; then
    rm -rf "$1"
  fi
}
