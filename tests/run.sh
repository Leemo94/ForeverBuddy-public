#!/bin/sh
# Runs every Lua unit test under luajit, once with the Classic fake client and once in Mainline
# mode. A file that fails to even parse counts as a failure: it prints no "passed" line, so the
# totals below are built from the files themselves, not from what they happened to print.
cd "$(dirname "$0")/.." || exit 1
status=0
files=0
broken=""
for mode in 0 1; do
  echo "#### FB_MAINLINE=$mode"
  for f in tests/test_*.lua; do
    echo "== $f"
    files=$((files + 1))
    if ! FB_MAINLINE=$mode "${LUAJIT:-luajit}" "$f"; then
      status=1
      broken="$broken $f"
    fi
  done
done
echo "#### $files test files run"
if [ -n "$broken" ]; then
  echo "#### FAILED:$broken"
else
  echo "#### all files passed"
fi
exit $status
