#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${1:-/opt/python}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Target directory '$TARGET_DIR' does not exist."
  exit 1
fi

echo "=========================================================="
echo ">> Starting Dependency Surgery on: $TARGET_DIR"
echo "=========================================================="

INITIAL_SIZE=$(du -sh "$TARGET_DIR" | cut -f1)
echo "Initial Layer Size: $INITIAL_SIZE"

# 1. Remove duplicate AWS SDKs (already provided natively by AWS Lambda Python runtime)
echo ">> Removing bundled botocore/boto3..."
rm -rf "$TARGET_DIR"/boto3* "$TARGET_DIR"/botocore* "$TARGET_DIR"/s3transfer*

# 2. Remove leaked developer, test, and documentation tooling
echo ">> Removing leaked build & documentation tooling..."
rm -rf "$TARGET_DIR"/sphinx* "$TARGET_DIR"/pre_commit* "$TARGET_DIR"/pytest* \
       "$TARGET_DIR"/babel* "$TARGET_DIR"/virtualenv* "$TARGET_DIR"/nodeenv* \
       "$TARGET_DIR"/sympy* "$TARGET_DIR"/pygments* "$TARGET_DIR"/docutils* \
       "$TARGET_DIR"/mpmath* "$TARGET_DIR"/jinja2* "$TARGET_DIR"/markupsafe*

# 3. Remove Python bytecode and caches
echo ">> Pruning __pycache__, *.pyc, *.pyo..."
find "$TARGET_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$TARGET_DIR" -type f -name "*.pyc" -delete
find "$TARGET_DIR" -type f -name "*.pyo" -delete

# 4. Strip unnecessary test suites, mocks, and docs
echo ">> Removing test suites, docs, and sample datasets..."
find "$TARGET_DIR" -type d \( \
    -name "tests" -o \
    -name "test" -o \
    -name "testing" -o \
    -name "unittest" -o \
    -name "docs" -o \
    -name "doc" -o \
    -name "examples" -o \
    -name "samples" \
\) -exec rm -rf {} + 2>/dev/null || true

# 5. Strip static non-runtime files (headers, C sources, documentation files)
echo ">> Stripping C/C++ headers, static docs, and metadata..."
find "$TARGET_DIR" -type f \( \
    -name "*.c" -o \
    -name "*.h" -o \
    -name "*.hpp" -o \
    -name "*.cpp" -o \
    -name "*.pyx" -o \
    -name "*.pxd" -o \
    -name "*.markdown" -o \
    -name "*.md" -o \
    -name "*.rst" -o \
    -name "*.txt" -o \
    -name "*.exe" \
\) -not -name "LICENSE*" -not -name "COPYING*" -delete

# 6. Clean .dist-info directories of RECORD and INSTALLER files (keep METADATA)
find "$TARGET_DIR" -type f -path "*.dist-info/RECORD" -delete 2>/dev/null || true
find "$TARGET_DIR" -type f -path "*.dist-info/INSTALLER" -delete 2>/dev/null || true

# 7. Strip debug symbols from ELF shared libraries (.so)
echo ">> Stripping ELF debug symbols from *.so binaries..."
SO_COUNT=0
while IFS= read -r so_file; do
    if [ -f "$so_file" ] && [ ! -L "$so_file" ]; then
        if file "$so_file" | grep -q "ELF"; then
            strip --strip-unneeded "$so_file" 2>/dev/null || true
            SO_COUNT=$((SO_COUNT + 1))
        fi
    fi
done < <(find "$TARGET_DIR" -type f -name "*.so*")

echo "Stripped $SO_COUNT shared library files."

FINAL_SIZE=$(du -sh "$TARGET_DIR" | cut -f1)
echo "=========================================================="
echo ">> Dependency Surgery Complete!"
echo ">> Initial Size: $INITIAL_SIZE"
echo ">> Final Size:   $FINAL_SIZE"
echo "=========================================================="
