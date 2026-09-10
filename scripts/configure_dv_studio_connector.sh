#!/usr/bin/env bash

###############################################################################
# Make an Apollo Studio plugin installer compatible with the Apollo runtime.
#
# Credentials and Dreamview metadata remain under $HOME. The active DAG loads
# the version-matched native component from /opt/apollo/neo instead of the
# binary bundled by a potentially older Studio installer.
###############################################################################

set -euo pipefail

TOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${TOP_DIR}/scripts/dv_plugin_runtime.sh"

PLUGIN_HOME="$(apollo_dv_studio_plugin_home)"
PLUGIN_DAG="${PLUGIN_HOME}/studio_connector.dag"
PLUGIN_LAUNCH="${PLUGIN_HOME}/studio_connector.launch"
PLUGIN_CONF="${PLUGIN_HOME}/studio_connector.conf"
PLUGIN_METADATA="${PLUGIN_HOME}/studio_connector_plugin_config.pb.txt"

if [[ ! -d "${PLUGIN_HOME}" ]]; then
  echo "[INFO] Apollo Studio plugin directory not found; skip compatibility setup."
  exit 0
fi

# The legacy plugin metadata contains a relative launch command. Dreamview+
# may itself run from /apollo_workspace, while the installed package launch
# file lives under /apollo. Use an explicit working directory so the plugin
# manager can authenticate and start the Connector from either layout.
configure_plugin_launch_command() {
  local package_root=""
  local candidate_root
  for candidate_root in \
    "${APOLLO_ROOT_DIR:-}" \
    "${APOLLO_DISTRIBUTION_HOME:-}" \
    "${APOLLO_RUNTIME_PATH:-}" \
    "/apollo"; do
    if [[ -n "${candidate_root}" &&
          -f "${candidate_root}/modules/studio_connector/studio_connector.launch" ]]; then
      package_root="${candidate_root}"
      break
    fi
  done
  if [[ -z "${package_root}" || ! -f "${PLUGIN_METADATA}" ]]; then
    return 0
  fi

  local launch_command="bash -lc 'cd ${package_root}; exec cyber_launch start modules/studio_connector/studio_connector.launch'"
  local stop_command="bash -lc 'cd ${package_root}; exec cyber_launch stop modules/studio_connector/studio_connector.launch'"
  sed -E -i \
    "s|^([[:space:]]*launch_command[[:space:]]*:[[:space:]]*).*$|\1\"${launch_command}\"|" \
    "${PLUGIN_METADATA}"
  sed -E -i \
    "s|^([[:space:]]*stop_command[[:space:]]*:[[:space:]]*).*$|\1\"${stop_command}\"|" \
    "${PLUGIN_METADATA}"
  echo "[INFO] Studio Connector launch command uses ${package_root}."
}

# Newer Apollo Studio installers may place only the account certificates and
# plugin metadata under $HOME. In that layout the version-matched package DAG
# under /apollo (or another distribution root) is the active launch target;
# there is no user DAG to rewrite.
if [[ ! -f "${PLUGIN_DAG}" ]]; then
  configure_plugin_launch_command
  echo "[INFO] No user Studio Connector DAG; use the installed package DAG."
  exit 0
fi

for required_file in "${PLUGIN_DAG}" "${PLUGIN_LAUNCH}" "${PLUGIN_CONF}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "[ERROR] Missing Apollo Studio plugin file: ${required_file}" >&2
    exit 1
  fi
done

COMPONENT_LIBRARY="$(apollo_dv_studio_component_library || true)"
if [[ -z "${COMPONENT_LIBRARY}" ]]; then
  echo "[ERROR] No version-matched studio_connector component was found." >&2
  echo "        Run: ./apollo.sh install_dv_plugins" >&2
  exit 1
fi

# Preserve the installer-generated DAG for rollback and debugging. The change
# is idempotent and only affects the native library/config paths.
if [[ ! -f "${PLUGIN_DAG}.installer-original" ]]; then
  cp -p "${PLUGIN_DAG}" "${PLUGIN_DAG}.installer-original"
fi

sed -E -i \
  "s|^([[:space:]]*module_library[[:space:]]*:[[:space:]]*).*$|\1\"${COMPONENT_LIBRARY}\"|" \
  "${PLUGIN_DAG}"
sed -E -i \
  "s|^([[:space:]]*flag_file_path[[:space:]]*:[[:space:]]*).*$|\1\"${PLUGIN_CONF}\"|" \
  "${PLUGIN_DAG}"

if ! grep -Fq "${COMPONENT_LIBRARY}" "${PLUGIN_DAG}" ||
  ! grep -Fq "${PLUGIN_CONF}" "${PLUGIN_DAG}"; then
  echo "[ERROR] Failed to configure the compatible studio_connector component." >&2
  exit 1
fi

configure_plugin_launch_command
echo "[INFO] studio_connector is configured to use ${COMPONENT_LIBRARY}."
