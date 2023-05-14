#!/bin/bash
# Common helper functions for entrypoint scripts

set -eo pipefail
shopt -s nullglob

DORIS_HOME="/opt/apache-doris"

# Logging functions
doris_log() {
  local type=$1
  shift
  # accept argument string or stdin
  local text="$*"
  if [ "$#" -eq 0 ]; then text="$(cat)"; fi
  local dt
  dt="$(date -Iseconds)"
  printf '%s [%s] [Entrypoint]: %s\n' "$dt" "$type" "$text"
}
doris_note() {
  doris_log NOTE "$@"
}
doris_warn() {
  doris_log WARN "$@" >&2
}
doris_error() {
  doris_log ERROR "$@" >&2
  exit 1
}

# Injects an entry in "key=value" format into the specified file when it does not exist.
inject_item_into_conf_file() {
  local conf_file=$1
  local key=$2
  local value=$3
  if ! grep -qE "^${key}\s*\=\s*${value}" "$conf_file"; then
    echo "" >>"$conf_file"
    echo "${key}=${value}" >>"$conf_file"
    doris_note "Inject '${key}=${value}' into ${conf_file}"
  fi
}

# Get the value corresponding to the key of the specified doris config file
# with optional default value.
get_value_from_conf_file() {
  local conf_file=$1
  local key=$2
  local default_value=$3
  local value
  value=$(grep "\<$key\>" "$conf_file" | grep -v '^\s*#' | sed 's|^\s*'"$key"'\s*=\s*\(.*\)\s*$|\1|g')
  if [[ -z $value && -n $default_value ]]; then
    value=$default_value
  fi
  echo "$value"
}

# Execute SQL statement with attached user and password information.
# -u is provided by the env var AUTH_USER and defaults to root;
# -p is provided by the env var AUTH_PWD.
exec_cmd() {
  set +e
  local cmd=$1
  if [[ -n $AUTH_USER ]]; then
    cmd="$cmd -u$AUTH_USER"
  else
    cmd="$cmd -uroot"
  fi
  if [[ -n $AUTH_PWD ]]; then
    cmd="$cmd -p$AUTH_PWD"
  fi
  eval cmd
}
