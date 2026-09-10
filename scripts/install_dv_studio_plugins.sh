#!/usr/bin/env bash

###############################################################################
# Copyright 2026 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
###############################################################################

set -euo pipefail

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
