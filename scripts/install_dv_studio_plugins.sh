#!/usr/bin/env bash

###############################################################################
# Copyright 2026 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
###############################################################################

set -euo pipefail

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${TOP_DIR}/scripts/dv_plugin_runtime.sh"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <Apollo Studio installer URL>" >&2
  exit 2
fi

INSTALL_URL="$1"

# 授权 URL 必须来自 Apollo Studio，不能把包含授权 token 的 URL 写进仓库。
if [[ "${INSTALL_URL}" != http://* && "${INSTALL_URL}" != https://* ]]; then
  echo "Error: installer URL must use http:// or https://" >&2
  exit 2
fi

# 远程安装脚本只在临时文件中执行，脚本结束后自动清理。
INSTALL_SCRIPT="$(mktemp /tmp/apollo-studio-connector-install.XXXXXX.sh)"
cleanup() {
  rm -f -- "${INSTALL_SCRIPT}"
}
trap cleanup EXIT

echo "Downloading Apollo Studio plugin installer..."
curl --fail --silent --show-error --location --retry 3 \
  --output "${INSTALL_SCRIPT}" "${INSTALL_URL}"
chmod 700 "${INSTALL_SCRIPT}"

# 安装包会把 studio_connector 和 sim_obstacle 放入 $HOME/.apollo/dreamview/plugins。
bash "${INSTALL_SCRIPT}"

# The signed installer supplies credentials and plugin metadata. The native
# component must come from the version-matched Apollo package.
# Otherwise the connector exits before Dreamview+ can authenticate or sync scenarios.
if ! command -v buildtool >/dev/null 2>&1; then
  echo "Error: buildtool is required to install the version-matched connector runtime." >&2
  exit 1
fi

PLUGIN_VERSION="$(apollo_dv_plugin_version || true)"
if [[ -z "${PLUGIN_VERSION}" ]]; then
  echo "Error: cannot determine the Apollo runtime version. Set APOLLO_STUDIO_PLUGIN_VERSION explicitly." >&2
  exit 1
fi

buildtool reinstall "simulator-plugin=${PLUGIN_VERSION}"
buildtool reinstall "studio-connector=${PLUGIN_VERSION}"
bash "${TOP_DIR}/scripts/configure_dv_studio_connector.sh"
