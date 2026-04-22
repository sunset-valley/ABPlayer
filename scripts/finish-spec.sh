#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: ./scripts/finish-spec.sh <spec-id>"
  echo "Example: ./scripts/finish-spec.sh 0001"
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

SPEC_ID="$1"

if [[ ! "$SPEC_ID" =~ ^[0-9]{4}$ ]]; then
  echo "Error: spec id must be a 4-digit number (for example: 0001)."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPECS_ROOT="$WORKSPACE_ROOT/Docs/specs"
FINISHED_ROOT="$WORKSPACE_ROOT/Docs/specs_finished"

if [ ! -d "$SPECS_ROOT" ]; then
  echo "Error: specs directory not found: $SPECS_ROOT"
  exit 1
fi

mkdir -p "$FINISHED_ROOT"

shopt -s nullglob
MATCHED_DIRS=()
for candidate in "$SPECS_ROOT"/"${SPEC_ID}"_*; do
  if [ -d "$candidate" ]; then
    MATCHED_DIRS+=("$candidate")
  fi
done
shopt -u nullglob

if [ "${#MATCHED_DIRS[@]}" -eq 0 ]; then
  echo "Error: spec $SPEC_ID not found under Docs/specs."
  exit 1
fi

if [ "${#MATCHED_DIRS[@]}" -gt 1 ]; then
  echo "Error: spec $SPEC_ID matched multiple directories under Docs/specs:"
  for match in "${MATCHED_DIRS[@]}"; do
    echo "- $(basename "$match")"
  done
  exit 1
fi

SOURCE_DIR="${MATCHED_DIRS[0]}"
SPEC_FILE="$SOURCE_DIR/spec.md"
PLAN_FILE="$SOURCE_DIR/plan.md"

if [ ! -f "$SPEC_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  echo "Error: $(basename "$SOURCE_DIR") must contain both spec.md and plan.md."
  exit 1
fi

TARGET_DIR="$FINISHED_ROOT/$(basename "$SOURCE_DIR")"
if [ -e "$TARGET_DIR" ]; then
  echo "Error: target already exists: $TARGET_DIR"
  exit 1
fi

mv "$SOURCE_DIR" "$TARGET_DIR"

echo "Finished spec archived successfully."
echo "From: $SOURCE_DIR"
echo "To:   $TARGET_DIR"
