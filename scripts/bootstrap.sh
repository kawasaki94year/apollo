#!/usr/bin/env bash

###############################################################################
# Copyright 2017-2021 The Apollo Authors. All Rights Reserved.
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

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DREAMVIEW_URL="http://localhost:8899"
DREAMVIEW_PLUS_URL="http://localhost:8888"

cd "${DIR}/.."

# Make sure supervisord has correct coredump file limit.
ulimit -c unlimited

source "${DIR}/apollo_base.sh"

function studio_connector_launch_file() {
  local user_launch="${HOME}/.apollo/dreamview/plugins/studio_connector/studio_connector.launch"
  if [[ -f "${user_launch}" ]]; then
    echo "${user_launch}"
    return 0
  fi
  # A development checkout can be mounted at /apollo_workspace while the
  # installed Connector launch file is linked into /apollo. Check all known
  # roots because APOLLO_DISTRIBUTION_HOME may correctly point to /opt/apollo/neo
  # for plugin binaries while the runtime package links remain under /apollo.
  local candidate_root
  for candidate_root in \
    "${APOLLO_ROOT_DIR:-}" \
    "${APOLLO_DISTRIBUTION_HOME:-}" \
    "${APOLLO_RUNTIME_PATH:-}" \
    "/apollo"; do
    if [[ -n "${candidate_root}" &&
          -f "${candidate_root}/modules/studio_connector/studio_connector.launch" ]]; then
      echo "${candidate_root}/modules/studio_connector/studio_connector.launch"
      return 0
    fi
  done
  return 1
}

function studio_connector_is_running() {
  # Bracket the first character so pgrep does not match its own command line.
  pgrep -f '[m]ainboard.*studio_connector.dag' >/dev/null 2>&1
}

function start_studio_connector() {
  local launch_file
  launch_file="$(studio_connector_launch_file || true)"
  if [[ -z "${launch_file}" ]]; then
    echo "Studio Connector is not installed; skipping plugin startup."
    return 0
  fi

  # Repair old Studio installer output while preserving account certificates.
  if [[ -x "${DIR}/configure_dv_studio_connector.sh" ]]; then
    bash "${DIR}/configure_dv_studio_connector.sh" || return 1
  fi

  # Dreamview's legacy PluginManager can start the Connector from the plugin
  # metadata at the same time as this bootstrap script. Wait briefly for that
  # asynchronous launch to become visible before starting a second instance;
  # duplicate Cyber nodes terminate one of the two processes.
  for _ in {1..10}; do
    if pgrep -f "[c]yber_launch start ${launch_file}" >/dev/null 2>&1 ||
      studio_connector_is_running; then
      echo "Studio Connector is already running."
      return 0
    fi
    sleep 0.5
  done

  echo "Starting Studio Connector ${launch_file}"
  # Package launch files use paths relative to their Apollo distribution root,
  # which can differ from the mounted source root in a development container.
  local launch_root="${APOLLO_ROOT_DIR}"
  # Package launch files refer to modules by a path relative to the directory
  # before /modules. Deriving it from the selected file also handles the
  # /apollo symlinks used by installed Neo packages.
  if [[ "${launch_file}" == */modules/* ]]; then
    launch_root="${launch_file%%/modules/*}"
  fi
  (
    cd "${launch_root}" || exit 1
    nohup cyber_launch start "${launch_file}" \
      >"${APOLLO_ROOT_DIR}/data/log/studio_connector.launch.out" 2>&1
  ) &
  sleep 2
  if ! studio_connector_is_running; then
    echo "Failed to start Studio Connector. Check ${APOLLO_ROOT_DIR}/data/log/studio_connector.launch.out" >&2
    return 1
  fi
}

function stop_studio_connector() {
  local launch_file
  launch_file="$(studio_connector_launch_file || true)"
  if [[ -z "${launch_file}" ]]; then
    return 0
  fi
  if studio_connector_is_running; then
    echo "Stopping Studio Connector"
    cyber_launch stop "${launch_file}" || true
  fi
}

function start() {
  for mod in ${APOLLO_BOOTSTRAP_EXTRA_MODULES}; do
    echo "Starting ${mod}"
    nohup cyber_launch start ${mod} &
  done
  ./scripts/monitor.sh start
  ./scripts/dreamview.sh start
  if [ $? -eq 0 ]; then
    sleep 2 # wait for some time before starting to check
    http_status="$(curl -o /dev/null -x '' -I -L -s -w '%{http_code}' ${DREAMVIEW_URL})"
    if [ $http_status -eq 200 ]; then
      echo "Dreamview is running at" $DREAMVIEW_URL
    else
      echo "Failed to start Dreamview. Please check /apollo/nohup.out or /apollo/data/core for more information"
    fi
  fi
}

function stop() {
  ./scripts/dreamview.sh stop
  ./scripts/monitor.sh stop
  for mod in ${APOLLO_BOOTSTRAP_EXTRA_MODULES}; do
    echo "Stopping ${mod}"
    nohup cyber_launch stop ${mod}
  done
}


function start_plus() {
  for mod in ${APOLLO_BOOTSTRAP_EXTRA_MODULES}; do
    echo "Starting ${mod}"
    nohup cyber_launch start ${mod} &
  done
  ./scripts/monitor.sh start
  ./scripts/dreamview_plus.sh start
  start_studio_connector
  if [ $? -eq 0 ]; then
    sleep 2 # wait for some time before starting to check
    http_status="$(curl -o /dev/null -x '' -I -L -s -w '%{http_code}' ${DREAMVIEW_PLUS_URL})"
    if [ $http_status -eq 200 ]; then
      echo "Dreamview Plus is running at" $DREAMVIEW_PLUS_URL
    else
      echo "Failed to start Dreamview Plus. Please check /apollo/nohup.out or /apollo/data/core for more information"
    fi
  fi
}

function stop_plus() {
  stop_studio_connector
  ./scripts/dreamview_plus.sh stop
  ./scripts/monitor.sh stop
  for mod in ${APOLLO_BOOTSTRAP_EXTRA_MODULES}; do
    echo "Stopping ${mod}"
    nohup cyber_launch stop ${mod}
  done
}

case $1 in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    start
    ;;
  start_plus)
    start_plus
    ;;
  stop_plus)
    stop_plus
    ;;
  restart_plus)
    stop_plus
    start_plus
    ;;
  *)
    start
    ;;
esac
