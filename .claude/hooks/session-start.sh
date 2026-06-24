#!/bin/bash
# Claude Code on the web: SessionStart hook.
# Installs the docs toolchain so the MkDocs build and the Vale linter work in
# remote sessions. Idempotent and non-interactive.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"

VENV_DIR="$PROJECT_DIR/.venv"
TOOLS_BIN="$PROJECT_DIR/.tools/bin"
VALE_VERSION="3.9.1"

# 1. Python deps for the MkDocs build.
# Use a virtualenv: the Debian system Python's patched distutils fails to build
# some of the pinned plugins (mkdocs-exclude). The venv avoids that.
if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
fi
# setuptools isn't bundled in Python 3.12 venvs and is needed to build
# mkdocs-exclude's wheel, so install it explicitly.
"$VENV_DIR/bin/pip" install --quiet --upgrade pip setuptools wheel
"$VENV_DIR/bin/pip" install --quiet -r "$PROJECT_DIR/requirements.txt"

# 2. Vale linter (matches the Run Vale CI check). Vendored styles live in
# styles/, so no `vale sync` is needed.
if [ ! -x "$TOOLS_BIN/vale" ]; then
  mkdir -p "$TOOLS_BIN"
  curl -sSL --max-time 120 \
    "https://github.com/errata-ai/vale/releases/download/v${VALE_VERSION}/vale_${VALE_VERSION}_Linux_64-bit.tar.gz" \
    -o /tmp/vale.tar.gz
  tar -xzf /tmp/vale.tar.gz -C "$TOOLS_BIN" vale
  rm -f /tmp/vale.tar.gz
fi

# 3. Put mkdocs and vale on PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$VENV_DIR/bin:$TOOLS_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

echo "Docs toolchain ready: $($VENV_DIR/bin/mkdocs --version) | $($TOOLS_BIN/vale --version)"
