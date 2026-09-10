#!/usr/bin/env bash

###############################################################################
# Copyright 2023 The Apollo Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${TOP_DIR}/scripts/apollo_base.sh"

set -e
set -o pipefail

# 插件安装会修改系统动态库配置；统一记录需要的系统级配置文件。
APOLLO_LD_CONF="/etc/ld.so.conf.d/apollo.conf"

# 容器内通常以 root 运行，宿主机或普通用户则通过 sudo 执行系统操作。
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
elif command -v sudo >/dev/null 2>&1; then
  SUDO=(sudo)
  if ! "${SUDO[@]}" -v; then
    error "Unable to obtain root privileges. Run this command in an Apollo host/container with working sudo."
    exit 1
  fi
else
  error "sudo is required when this script is not run as root."
  exit 1
fi

run_as_root() {
  "${SUDO[@]}" "$@"
}

mkdir -p /opt/apollo/neo/src
# buildtool 使用该目录保存包索引；目录不存在时会导致 available_check 创建失败。
mkdir -p "${APOLLO_CONFIG_HOME}"

install_buildtool() {
  if command -v buildtool >/dev/null 2>&1; then
    return
  fi

  for command_name in apt-get curl gpg dpkg; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      error "Required command not found: ${command_name}"
      exit 1
    fi
  done

  # 安装脚本原先将 buildtool 安装逻辑注释掉，导致插件命令直接找不到。
  info "buildtool was not found; installing apollo-neo-buildtool."
  run_as_root apt-get install -y ca-certificates curl gnupg
  run_as_root install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://apollo-pkg-beta.cdn.bcebos.com/neo/beta/key/deb.gpg.key | \
    run_as_root gpg --dearmor --yes -o /etc/apt/keyrings/apolloauto.gpg
  run_as_root chmod a+r /etc/apt/keyrings/apolloauto.gpg

  local codename
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}")"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/apolloauto.gpg] https://apollo-pkg-beta.cdn.bcebos.com/apollo/core %s main\n' \
    "$(dpkg --print-architecture)" "${codename}" | \
    run_as_root tee /etc/apt/sources.list.d/apolloauto.list >/dev/null
  run_as_root apt-get update
  run_as_root apt-get install -y apollo-neo-buildtool

  if [[ -f /opt/apollo/neo/setup.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/apollo/neo/setup.sh
  fi

  if ! command -v buildtool >/dev/null 2>&1; then
    error "apollo-neo-buildtool was installed, but buildtool is still unavailable in PATH."
    exit 1
  fi
}

install_buildtool

if [[ ! -f "${APOLLO_LD_CONF}" ]]; then
  error "Missing ${APOLLO_LD_CONF}. Initialize the Apollo environment before installing Dreamview plugins."
  exit 1
fi

run_as_root cp -f "${APOLLO_LD_CONF}" /etc/ld.so.conf.d/apollo_source.conf

# 逐个重新安装 Dreamview 依赖插件；任何一个包失败都立即终止，避免误报成功。
buildtool reinstall 3rd-tf2 3rd-civetweb 3rd-ad-rss-lib
buildtool reinstall studio-connector
buildtool reinstall sim-obstacle

run_as_root cp -f "${APOLLO_LD_CONF}" /etc/ld.so.conf.d/apollo_pkg.conf

# remove buildtool
# sudo apt remove -y apollo-neo-buildtool

# mv /opt/apollo/neo/setup.sh.bak /opt/apollo/neo/setup.sh

run_as_root ldconfig

ok "Successfully install dreamview plugins."
ok "Please restart dreamview. Enjoy!"
