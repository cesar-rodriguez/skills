#!/usr/bin/env bash
# resolve_go_imports.sh — Resolves git merge conflicts in Go import blocks.
#
# Usage: resolve_go_imports.sh <file_with_conflicts>
#
# Strategy:
#   1. Extract all imports from both sides of every conflict
#   2. Deduplicate
#   3. Sort within groups (stdlib / external / internal), preserving blank-line grouping
#   4. Rewrite the import block
#
# Exit codes:
#   0 — resolved successfully
#   1 — no import conflicts found (or file has non-import conflicts remaining)
#   2 — error

set -euo pipefail

FILE="${1:?Usage: resolve_go_imports.sh <file>}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 2
fi

# Check if file has conflict markers
if ! grep -q '^<<<<<<<' "$FILE"; then
  echo "No conflict markers found in $FILE" >&2
  exit 1
fi

# Create temp files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

RESOLVED="$TMPDIR/resolved.go"
ALL_IMPORTS="$TMPDIR/all_imports.txt"

# State machine to process the file
# States: normal, in_import, in_conflict_import, in_conflict_other
awk '
BEGIN {
  state = "normal"
  in_import_block = 0
  conflict_in_import = 0
  import_count = 0
  # We collect all unique imports
}

# Track whether we are inside an import ( ... ) block
/^import \(/ {
  in_import_block = 1
  print
  next
}

in_import_block && /^\)/ {
  in_import_block = 0
  # Before closing, dump collected conflict imports if any
  print
  next
}

# Inside import block — handle conflict markers
in_import_block && /^<<<<<<</ {
  conflict_in_import = 1
  next
}

in_import_block && conflict_in_import && /^=======/ {
  # Switch from ours to theirs — just keep collecting
  next
}

in_import_block && conflict_in_import && /^>>>>>>>/ {
  conflict_in_import = 0
  next
}

# Inside import block (conflict or not) — collect import lines
in_import_block {
  # Strip leading/trailing whitespace for dedup, but print with tab
  line = $0
  gsub(/^[ \t]+/, "", line)
  gsub(/[ \t]+$/, "", line)
  if (line == "") {
    # Blank line = group separator, preserve one
    print ""
  } else if (!(line in seen)) {
    seen[line] = 1
    print "\t" line
  }
  next
}

# Outside import block — handle conflicts (pass through or flag)
/^<<<<<<</ && !in_import_block {
  has_non_import_conflict = 1
  print
  next
}

{ print }

END {
  if (has_non_import_conflict) {
    exit 1
  }
}
' "$FILE" > "$RESOLVED"

EXIT_CODE=${PIPESTATUS[0]:-$?}

if [[ $EXIT_CODE -eq 1 ]]; then
  echo "WARN: Non-import conflicts remain in $FILE" >&2
fi

# Now sort imports within groups
# We need a second pass to sort each import group
python3 - "$RESOLVED" "$FILE" << 'PYTHON'
import sys
import re

resolved_path = sys.argv[1]
output_path = sys.argv[2]

with open(resolved_path, 'r') as f:
    content = f.read()

def sort_import_block(match):
    """Sort imports within an import() block, preserving groups."""
    block = match.group(0)
    lines = block.split('\n')
    
    # First and last lines are "import (" and ")"
    header = lines[0]
    footer = lines[-1]
    body = lines[1:-1]
    
    # Split into groups by blank lines
    groups = []
    current_group = []
    for line in body:
        stripped = line.strip()
        if stripped == '':
            if current_group:
                groups.append(current_group)
                current_group = []
        else:
            current_group.append(line)
    if current_group:
        groups.append(current_group)
    
    # Classify and sort each group
    # Groups: stdlib (no dot in path), external (has dot)
    stdlib = []
    external = []
    
    for group in groups:
        for line in group:
            stripped = line.strip()
            # Determine if stdlib or external
            # Extract the import path (inside quotes)
            path_match = re.search(r'"([^"]+)"', stripped)
            if path_match:
                path = path_match.group(1)
                if '.' in path.split('/')[0]:
                    external.append(stripped)
                else:
                    stdlib.append(stripped)
            elif stripped.startswith('_') or stripped.startswith('//'):
                # Blank import or comment — check the quoted path
                path_match = re.search(r'"([^"]+)"', stripped)
                if path_match and '.' in path_match.group(1).split('/')[0]:
                    external.append(stripped)
                else:
                    stdlib.append(stripped)
    
    # Sort each group
    stdlib.sort(key=lambda x: re.search(r'"([^"]+)"', x).group(1) if re.search(r'"([^"]+)"', x) else x)
    external.sort(key=lambda x: re.search(r'"([^"]+)"', x).group(1) if re.search(r'"([^"]+)"', x) else x)
    
    # Rebuild
    result = [header]
    if stdlib:
        for imp in stdlib:
            result.append('\t' + imp)
    if stdlib and external:
        result.append('')
    if external:
        for imp in external:
            result.append('\t' + imp)
    result.append(footer)
    
    return '\n'.join(result)

# Match import blocks
pattern = r'^import \(.*?^\)'
content = re.sub(pattern, sort_import_block, content, flags=re.MULTILINE | re.DOTALL)

with open(output_path, 'w') as f:
    f.write(content)

PYTHON

echo "Resolved import conflicts in $FILE"
