#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs the toolchain needed to build the docs and run the Vale linter.
# Safe to run repeatedly (idempotent) and requires no user input.
#
# Runs asynchronously: the session starts immediately while dependencies
# install in the background. Faster startup, but a build or lint issued in the
# first few seconds may run before the toolchain is ready.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment. Local machines
# are expected to already have their own setup.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Tell the harness to run this hook in the background. Must be the first line
# of stdout. asyncTimeout is generous to cover a cold pip install + Vale fetch.
echo '{"async": true, "asyncTimeout": 600000}'

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR"

VENV_DIR="$PROJECT_DIR/.venv"
TOOLS_BIN="$PROJECT_DIR/.tools/bin"
VALE_VERSION="3.9.1"

echo "[session-start] Setting up Python virtual environment..."
# The system Python is Debian-patched and fails to build some sdists
# (mkdocs-exclude). A venv avoids the patched distutils.
if [ ! -x "$VENV_DIR/bin/python" ]; then
  python3 -m venv "$VENV_DIR"
fi

# Python 3.12 venvs don't bundle setuptools, which mkdocs-exclude needs to build.
"$VENV_DIR/bin/pip" install --quiet --upgrade pip setuptools wheel

echo "[session-start] Installing docs dependencies (requirements.txt)..."
# External contributors use the free Material for MkDocs (already pinned in
# requirements.txt); the Insiders submodule isn't available here.
"$VENV_DIR/bin/pip" install --quiet -r requirements.txt

echo "[session-start] Installing Vale linter (v${VALE_VERSION})..."
mkdir -p "$TOOLS_BIN"
if [ ! -x "$TOOLS_BIN/vale" ] || ! "$TOOLS_BIN/vale" --version 2>/dev/null | grep -q "$VALE_VERSION"; then
  curl -sSL --max-time 120 \
    "https://github.com/errata-ai/vale/releases/download/v${VALE_VERSION}/vale_${VALE_VERSION}_Linux_64-bit.tar.gz" \
    -o /tmp/vale.tar.gz
  tar -xzf /tmp/vale.tar.gz -C "$TOOLS_BIN" vale
  rm -f /tmp/vale.tar.gz
fi

# Persist the venv and Vale binary on PATH for the rest of the session so
# `mkdocs` and `vale` are directly callable.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$VENV_DIR/bin:$TOOLS_BIN:\$PATH\""
    echo "export NO_TEMPLATE=true"
  } >> "$CLAUDE_ENV_FILE"
fi

echo "[session-start] Done. mkdocs: $("$VENV_DIR/bin/mkdocs" --version 2>/dev/null) | vale: $("$TOOLS_BIN/vale" --version)"
