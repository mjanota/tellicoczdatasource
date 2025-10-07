#!/bin/bash

# Databazeknih Search Script Wrapper
# This script runs the Python databazeknih search tool with uv

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/databazeknih/databazeknih_search_my.py"

# Check if the Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found at $PYTHON_SCRIPT"
    exit 1
fi

# Check if uv is available
if ! command -v uv &> /dev/null; then
    echo "Error: uv is not installed or not in PATH"
    echo "Please install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
fi

# Create log file with timestamp
LOG_FILE="/tmp/databazeknih_search_$(date +%Y%m%d_%H%M%S).log"

# Change to the databazeknih directory to ensure proper working directory
cd "$SCRIPT_DIR/databazeknih"

# Run the Python script with uv, passing all arguments
# Redirect stderr to log file while keeping stdout for XML output
uv run "$PYTHON_SCRIPT" "$@" 2>"$LOG_FILE"