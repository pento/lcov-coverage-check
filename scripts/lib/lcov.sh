# Source guard — prevent double-sourcing
[[ -n "${_LIB_LCOV_LOADED:-}" ]] && return 0
_LIB_LCOV_LOADED=1

# ---------------------------------------------------------------------------
# LCOV parsing
# ---------------------------------------------------------------------------

# parse_lcov_overall FILE
#   Prints a single line: "hit found percentage"
#   If the file is empty or missing, prints "0 0 0"
parse_lcov_overall() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "0 0 0"
    return
  fi
  awk '
    BEGIN { total_hit = 0; total_found = 0 }
    /^LH:/ { total_hit += substr($0, 4) }
    /^LF:/ { total_found += substr($0, 4) }
    END {
      if (total_found > 0)
        printf "%d %d %.4f\n", total_hit, total_found, (total_hit / total_found) * 100
      else
        printf "0 0 0\n"
    }
  ' "$file"
}

# parse_lcov_per_file FILE
#   Prints lines of: "filepath hit found"
#   One line per source file record.
parse_lcov_per_file() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    return
  fi
  awk '
    /^SF:/ { sf = substr($0, 4); hit = 0; found = 0 }
    /^LH:/ { hit = substr($0, 4) }
    /^LF:/ { found = substr($0, 4) }
    /^end_of_record/ { print sf, hit, found }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Numeric helpers
# ---------------------------------------------------------------------------

# coverage_pct HIT FOUND — prints percentage via awk
coverage_pct() {
  awk -v h="$1" -v f="$2" 'BEGIN {
    if (f+0 > 0) printf "%.4f", (h / f) * 100; else printf "0"
  }'
}

# compare_floats A OP B — returns 0 (true) or 1 (false)
#   OP: "lt", "le", "gt", "ge", "eq"
compare_floats() {
  awk -v a="$1" -v op="$2" -v b="$3" 'BEGIN {
    if (op == "lt") exit !(a + 0 < b + 0)
    if (op == "le") exit !(a + 0 <= b + 0)
    if (op == "gt") exit !(a + 0 > b + 0)
    if (op == "ge") exit !(a + 0 >= b + 0)
    if (op == "eq") exit !(a + 0 == b + 0)
    exit 1
  }'
}

# format_pct VALUE — prints value with 2 decimal places
format_pct() {
  awk -v v="$1" 'BEGIN { printf "%.2f", v + 0 }'
}

# extract_lcov_extensions FILE
#   Prints unique file extensions found in SF: lines (e.g., ".dart", ".ts")
extract_lcov_extensions() {
  local file="$1"
  [[ ! -s "$file" ]] && return
  awk '/^SF:/ {
    sf = substr($0, 4)
    n = split(sf, parts, ".")
    if (n > 1) print "." parts[n]
  }' "$file" | sort -u
}
