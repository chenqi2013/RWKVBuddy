#!/bin/sh
set -eu

service_root="$PROJECT_DIR/../agent-service"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/agent-service"
if [ ! -x "$service_root/runtime/node" ] || [ ! -x "$service_root/runtime/lua" ]; then
  echo 'error: macOS runtimes missing. Run: python3 scripts/prepare-macos-runtime.py' >&2
  exit 1
fi
if [ ! -d "$service_root/node_modules/docx" ] || [ ! -d "$service_root/node_modules/exceljs" ]; then
  echo 'error: Service dependencies missing. Run: npm ci --prefix agent-service --omit=optional --ignore-scripts' >&2
  exit 1
fi
mkdir -p "$destination"
rsync -a --delete --exclude '/test/' --exclude '/default-connection.json' --exclude '/runtime/' \
  --exclude '.venv' --exclude '__pycache__' --exclude 'test_server.py' --exclude 'server.py' --exclude '/local-model/native/' \
  --exclude '.DS_Store' --exclude '._*' "$service_root/" "$destination/"
mkdir -p "$destination/runtime"
cp "$service_root/runtime/node" "$service_root/runtime/lua" "$destination/runtime/"
if [ -d "$service_root/runtime/llama" ]; then
  rsync -a --delete --exclude 'llama-server' --exclude 'llama-server.exe' "$service_root/runtime/llama/" "$destination/runtime/llama/"
  find "$destination/runtime/llama" -name rwkvbuddy-inference -type f -exec \
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" {} \;
fi
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
  --entitlements "$PROJECT_DIR/Runner/Node.entitlements" "$destination/runtime/node"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$destination/runtime/lua"
