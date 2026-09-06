#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h:h}"
mkdir -p "$TASK_ROOT/work/editor-tests"
swiftc -D EDITOR_TESTS "$TASK_ROOT/Sources/ShotKey/Editor.swift" \
  "$TASK_ROOT/Tests/ShotKeyTests/EditorTests.swift" \
  "$TASK_ROOT/Tools/test-support/main.swift" \
  -o "$TASK_ROOT/work/editor-tests/run" -framework AppKit -framework ScreenCaptureKit -framework CoreImage
"$TASK_ROOT/work/editor-tests/run" "$TASK_ROOT/work/editor-tests"
