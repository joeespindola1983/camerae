#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "uso: bash scripts/compare_stacks.sh /caminho/para/frames [profile]"
  exit 1
fi

INPUT_DIR="$1"
PROFILE="${2:-milkyway}"
BIN="./build/camerae-astro-preview"

if [[ ! -x "$BIN" ]]; then
  echo "binario nao encontrado: $BIN"
  echo "rode: cmake -S . -B build && cmake --build build"
  exit 1
fi

mkdir -p out

for STACK in 5 10 15 30; do
  "$BIN" \
    --input "$INPUT_DIR" \
    --output "out/${PROFILE}_stack_${STACK}.jpg" \
    --profile "$PROFILE" \
    --stack "$STACK"
done

echo "previews gerados em ./out"
