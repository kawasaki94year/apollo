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

if [[ ! -d "${PLUGIN_HOME}" ]]; then
  echo "[INFO] Apollo Studio plugin directory not found; skip compatibility setup."
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

echo "[INFO] studio_connector is configured to use ${COMPONENT_LIBRARY}."
