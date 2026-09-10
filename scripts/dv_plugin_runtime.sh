#!/usr/bin/env bash

###############################################################################
# Shared Dreamview plugin runtime helpers.
#
# Apollo Studio places plugin files under $HOME. The native component must be
# loaded from the Apollo package built for the same release, otherwise Cyber
# reports missing or ABI-incompatible shared libraries.
###############################################################################

# Return the package version matching the installed Apollo buildtool.
# Operators can override it for a custom package repository.
apollo_dv_plugin_version() {
  if [[ -n "${APOLLO_STUDIO_PLUGIN_VERSION:-}" ]]; then
    printf '%s\n' "${APOLLO_STUDIO_PLUGIN_VERSION}"
    return 0
  fi

  local module_conf="/opt/apollo/neo/packages/buildtool/latest/config/module.conf"
  local buildtool_version=""
  if [[ -f "${module_conf}" ]]; then
    buildtool_version="$(sed -n 's/^version[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "${module_conf}" | head -n 1)"
  fi

  # buildtool versions may contain a suffix such as -rc1-r1, while module
  # packages are published as major.minor.patch.
  buildtool_version="${buildtool_version%%-*}"
  if [[ "${buildtool_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "${buildtool_version}"
    return 0
  fi

  return 1
}

apollo_dv_studio_plugin_home() {
  printf '%s\n' "${HOME}/.apollo/dreamview/plugins/studio_connector"
}

apollo_dv_studio_component_library() {
  local candidate
  for candidate in \
    "/opt/apollo/neo/lib/modules/studio_connector/libstudio_connector_component.so" \
    "${APOLLO_ROOT_DIR:-}/bazel-bin/modules/studio_connector/libstudio_connector_component.so"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}
