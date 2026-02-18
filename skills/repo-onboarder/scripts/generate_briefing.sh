#!/usr/bin/env bash
set -euo pipefail

# repo-onboarder: Generate compact repo briefing for subagent prompt injection
# Usage: generate_briefing.sh <org/repo | github-url> [--force]

WORKSPACE="${WORKSPACE:-${HOME}/.skills-workspace}"
BRIEFINGS_DIR="${WORKSPACE}/repo-briefings"
CLONE_BASE="/tmp/repo-onboarder"

mkdir -p "$BRIEFINGS_DIR" "$CLONE_BASE"

# --- Parse arguments ---
REPO_INPUT="${1:?Usage: generate_briefing.sh <org/repo or github-url> [--force]}"
FORCE="${2:-}"

# Normalize repo input: extract org/repo from URL or direct input
REPO_SLUG=$(echo "$REPO_INPUT" | sed -E 's|^https?://github\.com/||; s|\.git$||; s|/$||')
ORG=$(echo "$REPO_SLUG" | cut -d'/' -f1)
REPO=$(echo "$REPO_SLUG" | cut -d'/' -f2)

if [[ -z "$ORG" || -z "$REPO" ]]; then
  echo "ERROR: Could not parse org/repo from: $REPO_INPUT" >&2
  exit 1
fi

BRIEFING_FILE="${BRIEFINGS_DIR}/${ORG}-${REPO}.md"
CLONE_DIR="${CLONE_BASE}/${ORG}-${REPO}"

# --- Cache check ---
if [[ -f "$BRIEFING_FILE" && "$FORCE" != "--force" ]]; then
  echo "Cached briefing exists: $BRIEFING_FILE"
  echo "Use --force to regenerate."
  exit 0
fi

echo "Generating briefing for ${ORG}/${REPO}..."

# --- Clone or update ---
if [[ -d "$CLONE_DIR/.git" ]]; then
  echo "Updating existing clone..."
  git -C "$CLONE_DIR" fetch --quiet origin 2>/dev/null || true
  git -C "$CLONE_DIR" reset --hard origin/HEAD --quiet 2>/dev/null || \
    git -C "$CLONE_DIR" reset --hard HEAD --quiet 2>/dev/null || true
else
  echo "Cloning ${ORG}/${REPO}..."
  rm -rf "$CLONE_DIR"
  git clone --depth=200 "https://github.com/${ORG}/${REPO}.git" "$CLONE_DIR" 2>/dev/null || \
    gh repo clone "${ORG}/${REPO}" "$CLONE_DIR" -- --depth=200 2>/dev/null
fi

cd "$CLONE_DIR"

# --- Language detection ---
LANGUAGES=()
BUILD_TOOLS=()
TEST_CMDS=()
LINT_CMDS=()

# Go
if [[ -f go.mod ]]; then
  LANGUAGES+=("Go $(grep '^go ' go.mod | awk '{print $2}')")
  BUILD_TOOLS+=("go build")
  TEST_CMDS+=("go test ./...")
  LINT_CMDS+=("golangci-lint run")
fi

# Node
if [[ -f package.json ]]; then
  NODE_VER=""
  if [[ -f .nvmrc ]]; then NODE_VER=" $(cat .nvmrc | tr -d '[:space:]')"; fi
  if [[ -f .node-version ]]; then NODE_VER=" $(cat .node-version | tr -d '[:space:]')"; fi
  LANGUAGES+=("Node${NODE_VER}")

  # Detect package manager
  if [[ -f pnpm-lock.yaml ]]; then BUILD_TOOLS+=("pnpm")
  elif [[ -f yarn.lock ]]; then BUILD_TOOLS+=("yarn")
  elif [[ -f bun.lockb ]]; then BUILD_TOOLS+=("bun")
  else BUILD_TOOLS+=("npm"); fi

  # Extract test/lint from scripts
  if command -v jq &>/dev/null; then
    PKG_MGR="${BUILD_TOOLS[-1]}"
    TEST_SCRIPT=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
    LINT_SCRIPT=$(jq -r '.scripts.lint // empty' package.json 2>/dev/null)
    [[ -n "$TEST_SCRIPT" ]] && TEST_CMDS+=("${PKG_MGR} test")
    [[ -n "$LINT_SCRIPT" ]] && LINT_CMDS+=("${PKG_MGR} run lint")
  fi
fi

# Python
if [[ -f pyproject.toml || -f setup.py || -f setup.cfg ]]; then
  PYTHON_VER=""
  if [[ -f .python-version ]]; then PYTHON_VER=" $(cat .python-version | tr -d '[:space:]')"; fi
  LANGUAGES+=("Python${PYTHON_VER}")

  if [[ -f pyproject.toml ]] && grep -q '\[tool\.poetry\]' pyproject.toml 2>/dev/null; then
    BUILD_TOOLS+=("poetry")
    TEST_CMDS+=("poetry run pytest")
    LINT_CMDS+=("poetry run ruff check .")
  elif [[ -f Pipfile ]]; then
    BUILD_TOOLS+=("pipenv")
    TEST_CMDS+=("pipenv run pytest")
  else
    BUILD_TOOLS+=("pip")
    TEST_CMDS+=("pytest")
    LINT_CMDS+=("ruff check .")
  fi
fi

# Rust
if [[ -f Cargo.toml ]]; then
  RUST_VER=""
  if [[ -f rust-toolchain.toml ]]; then
    RUST_VER=" $(grep 'channel' rust-toolchain.toml 2>/dev/null | head -1 | sed 's/.*= *"//;s/".*//')"
  fi
  LANGUAGES+=("Rust${RUST_VER}")
  BUILD_TOOLS+=("cargo")
  TEST_CMDS+=("cargo test")
  LINT_CMDS+=("cargo clippy")
fi

# Makefile
if [[ -f Makefile ]]; then
  BUILD_TOOLS+=("make")
  # Extract common make targets
  MAKE_TARGETS=$(grep -E '^[a-zA-Z_-]+:' Makefile | head -20 | sed 's/:.*//' | tr '\n' ' ')
fi

# --- CI detection ---
CI_INFO=""
if [[ -d .github/workflows ]]; then
  CI_FILES=$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | head -5)
  CI_INFO="GitHub Actions ($(echo "$CI_FILES" | xargs -I{} basename {} | tr '\n' ', ' | sed 's/,$//'))"
elif [[ -f .gitlab-ci.yml ]]; then
  CI_INFO="GitLab CI (.gitlab-ci.yml)"
elif [[ -f Jenkinsfile ]]; then
  CI_INFO="Jenkins (Jenkinsfile)"
elif [[ -f .circleci/config.yml ]]; then
  CI_INFO="CircleCI (.circleci/config.yml)"
fi

# --- Directory layout ---
TREE_OUTPUT=$(find . -maxdepth 2 -type d \
  ! -path './.git*' \
  ! -path './node_modules*' \
  ! -path './vendor*' \
  ! -path './.next*' \
  ! -path './dist*' \
  ! -path './build*' \
  ! -path './__pycache__*' \
  ! -path './.venv*' \
  ! -path './target*' \
  | sed 's|^\./||' | sort | head -40)

# Annotate key directories
annotate_dir() {
  local dir="$1"
  case "$dir" in
    cmd|cmd/*) echo "${dir}/ — CLI entrypoints";;
    pkg|pkg/*) echo "${dir}/ — library packages";;
    internal|internal/*) echo "${dir}/ — internal packages";;
    api|api/*) echo "${dir}/ — API definitions";;
    src) echo "${dir}/ — source code";;
    lib|lib/*) echo "${dir}/ — library code";;
    test|tests|test/*|tests/*) echo "${dir}/ — tests";;
    docs|doc) echo "${dir}/ — documentation";;
    scripts) echo "${dir}/ — build/utility scripts";;
    .github|.github/*) echo "${dir}/ — GitHub config";;
    *) echo "${dir}/";;
  esac
}

# --- Hot files (git churn analysis) ---
HOT_FILES=""
if git log --oneline -1 &>/dev/null; then
  HOT_FILES=$(git log --format='' --name-only 2>/dev/null \
    | grep -v '^$' \
    | sort | uniq -c | sort -rn \
    | head -20 \
    | awk '{printf "- %s (%d changes)\n", $2, $1}')
fi

# --- Go-specific analysis ---
GO_PACKAGES=""
GO_MODULE=""
if [[ -f go.mod ]]; then
  GO_MODULE=$(head -1 go.mod | awk '{print $2}')
  # List packages from directory structure (no go toolchain needed)
  GO_PACKAGES=$(find . -name '*.go' -not -path './vendor/*' \
    | xargs -I{} dirname {} | sort -u | sed 's|^\./||' \
    | head -30 \
    | awk -v mod="$GO_MODULE" '{if ($0 == ".") print mod; else print mod "/" $0}')
fi

# --- Node-specific analysis ---
NODE_WORKSPACES=""
NODE_SCRIPTS=""
if [[ -f package.json ]] && command -v jq &>/dev/null; then
  NODE_WORKSPACES=$(jq -r '.workspaces // [] | .[]' package.json 2>/dev/null | head -10)
  NODE_SCRIPTS=$(jq -r '.scripts // {} | keys[]' package.json 2>/dev/null | head -15 | tr '\n' ', ' | sed 's/,$//')
fi

# --- Python-specific analysis ---
PY_MODULES=""
if [[ -f pyproject.toml || -f setup.py ]]; then
  PY_MODULES=$(find . -name '__init__.py' -not -path './venv/*' -not -path './.venv/*' \
    | xargs -I{} dirname {} | sed 's|^\./||' | sort | head -20)
fi

# --- Read existing docs for conventions ---
CONVENTIONS_FROM_DOCS=""
for doc in README.md CONTRIBUTING.md AGENTS.md CLAUDE.md; do
  if [[ -f "$doc" ]]; then
    # Extract convention-like sections (limited to keep briefing compact)
    SECTION=$(awk '/^##.*[Cc]onvention|^##.*[Ss]tyle|^##.*[Cc]ontribut|^##.*[Dd]evelop|^##.*[Ss]etup|^##.*[Tt]est|^##.*[Ll]int/{found=1} found{print; if(/^##/ && NR>1) found=0}' "$doc" 2>/dev/null | head -20)
    if [[ -n "$SECTION" ]]; then
      CONVENTIONS_FROM_DOCS+="From ${doc}:
${SECTION}
"
    fi
  fi
done

# --- Detect conventions from code patterns ---
CODE_CONVENTIONS=""

# Test file placement
if find . -name '*_test.go' -maxdepth 3 | head -1 | grep -q .; then
  CODE_CONVENTIONS+="- Go tests: co-located (*_test.go alongside source)\n"
fi
if find . -name '*.test.ts' -o -name '*.test.js' -o -name '*.spec.ts' -o -name '*.spec.js' 2>/dev/null | head -1 | grep -q .; then
  if find . -path '*/__tests__/*' -maxdepth 4 | head -1 | grep -q .; then
    CODE_CONVENTIONS+="- JS/TS tests: __tests__/ directories\n"
  else
    CODE_CONVENTIONS+="- JS/TS tests: co-located (.test/.spec files)\n"
  fi
fi
if find . -name 'test_*.py' -o -name '*_test.py' 2>/dev/null | head -1 | grep -q .; then
  if [[ -d tests ]]; then
    CODE_CONVENTIONS+="- Python tests: tests/ directory\n"
  else
    CODE_CONVENTIONS+="- Python tests: co-located\n"
  fi
fi

# Config files indicating style tools
[[ -f .eslintrc* || -f .eslintrc.js || -f .eslintrc.json || -f eslint.config.* ]] && CODE_CONVENTIONS+="- Linter: ESLint\n"
[[ -f .prettierrc* || -f prettier.config.* ]] && CODE_CONVENTIONS+="- Formatter: Prettier\n"
[[ -f .golangci.yml || -f .golangci.yaml ]] && CODE_CONVENTIONS+="- Linter: golangci-lint\n"
[[ -f ruff.toml ]] && CODE_CONVENTIONS+="- Linter: Ruff\n"
[[ -f .editorconfig ]] && CODE_CONVENTIONS+="- EditorConfig present\n"

# --- File counts ---
TOTAL_FILES=$(find . -type f ! -path './.git/*' ! -path './node_modules/*' ! -path './vendor/*' ! -path './target/*' | wc -l | tr -d ' ')
GO_FILES=$(find . -name '*.go' ! -path './vendor/*' 2>/dev/null | wc -l | tr -d ' ')
JS_FILES=$(find . \( -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' \) ! -path './node_modules/*' 2>/dev/null | wc -l | tr -d ' ')
PY_FILES=$(find . -name '*.py' ! -path './.venv/*' ! -path './venv/*' 2>/dev/null | wc -l | tr -d ' ')
RS_FILES=$(find . -name '*.rs' ! -path './target/*' 2>/dev/null | wc -l | tr -d ' ')

# --- Generate briefing ---
{
  echo "# Repo Briefing: ${ORG}/${REPO}"
  echo ""
  echo "## Quick Facts"
  echo "- **Languages:** ${LANGUAGES[*]:-unknown}"
  echo "- **Build:** ${BUILD_TOOLS[*]:-unknown}"
  [[ -n "$CI_INFO" ]] && echo "- **CI:** ${CI_INFO}"
  echo "- **Files:** ${TOTAL_FILES} total"
  [[ "$GO_FILES" -gt 0 ]] && echo "  - Go: ${GO_FILES}"
  [[ "$JS_FILES" -gt 0 ]] && echo "  - JS/TS: ${JS_FILES}"
  [[ "$PY_FILES" -gt 0 ]] && echo "  - Python: ${PY_FILES}"
  [[ "$RS_FILES" -gt 0 ]] && echo "  - Rust: ${RS_FILES}"

  echo ""
  echo "## Directory Layout"
  echo '```'
  while IFS= read -r dir; do
    [[ -z "$dir" || "$dir" == "." ]] && continue
    annotate_dir "$dir"
  done <<< "$TREE_OUTPUT"
  echo '```'

  echo ""
  echo "## Conventions"
  if [[ -n "$CODE_CONVENTIONS" ]]; then
    echo -e "$CODE_CONVENTIONS"
  fi
  if [[ -n "$CONVENTIONS_FROM_DOCS" ]]; then
    echo "$CONVENTIONS_FROM_DOCS"
  fi
  if [[ -z "$CODE_CONVENTIONS" && -z "$CONVENTIONS_FROM_DOCS" ]]; then
    echo "_No explicit conventions detected. Check code for patterns._"
  fi

  echo ""
  echo "## Hot Files (high merge-conflict risk)"
  if [[ -n "$HOT_FILES" ]]; then
    echo "$HOT_FILES"
  else
    echo "_Insufficient git history for churn analysis._"
  fi

  echo ""
  echo "## Key Packages/Modules"
  if [[ -n "$GO_MODULE" ]]; then
    echo "### Go Module: \`${GO_MODULE}\`"
    echo '```'
    echo "$GO_PACKAGES"
    echo '```'
  fi
  if [[ -n "$NODE_WORKSPACES" ]]; then
    echo "### Node Workspaces"
    echo "$NODE_WORKSPACES" | while read -r ws; do echo "- ${ws}"; done
  fi
  if [[ -n "$NODE_SCRIPTS" ]]; then
    echo "### package.json scripts"
    echo "\`${NODE_SCRIPTS}\`"
  fi
  if [[ -n "$PY_MODULES" ]]; then
    echo "### Python Modules"
    echo '```'
    echo "$PY_MODULES"
    echo '```'
  fi

  echo ""
  echo "## Test Commands"
  if [[ ${#TEST_CMDS[@]} -gt 0 ]]; then
    for cmd in "${TEST_CMDS[@]}"; do echo "- \`${cmd}\`"; done
  else
    echo "- _No test commands detected_"
  fi
  if [[ ${#LINT_CMDS[@]} -gt 0 ]]; then
    echo ""
    echo "## Lint Commands"
    for cmd in "${LINT_CMDS[@]}"; do echo "- \`${cmd}\`"; done
  fi

  if [[ -n "${MAKE_TARGETS:-}" ]]; then
    echo ""
    echo "## Makefile Targets"
    echo "\`${MAKE_TARGETS}\`"
  fi

  echo ""
  echo "---"
  echo "_Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) by repo-onboarder_"

} > "$BRIEFING_FILE"

echo ""
echo "✅ Briefing written to: ${BRIEFING_FILE}"
echo "   Size: $(wc -w < "$BRIEFING_FILE") words, $(wc -l < "$BRIEFING_FILE") lines"
