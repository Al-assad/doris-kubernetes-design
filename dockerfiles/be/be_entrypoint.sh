#!/bin/bash

# Extra environment variables:
#  FE_SVC: FE service name, required.
#  FE_QUERY_PORT: FE service query port, optional, default: 9030
#  AUTH_USER: account name to execute sql, optional, default: root
#  AUTH_PWD: account password to execute sql, optional.

source entrypoint_helper.sh

BE_CONF_FILE=${DORIS_HOME}/be/conf/be.conf

# pod fqdn host
declare POD_HOST
# doris be heartbeat port
declare HEARTBEAT_PORT
# doris fe query port
declare FE_QUERY_PORT

# be probe interval: 2 seconds
BE_PROBE_INTERVAL=2
# timeout for probe cn: 60 seconds
BE_PROBE_TIMEOUT=60

# collect env info from container
collect_env() {
  POD_HOST=$(hostname -f)
  HEARTBEAT_PORT=$(get_value_from_conf_file "$BE_CONF_FILE" 'heartbeat_service_port' 9050)
  if [[ -z $FE_QUERY_PORT ]]; then
    FE_QUERY_PORT=9030
  fi
}

# make sure node role is mix
ensure_node_role() {
  inject_item_into_conf_file "$BE_CONF_FILE" 'be_node_role' 'computation'
}

show_backends() {
  exec_sql "timeout 15 mysql --connect-timeout 2 -h $FE_SVC -P $QUERY_PORT --skip-column-names --batch -e 'SHOW FRONTENDS;'"
}

# add self to cluster
add_self() {
  set +e
  local start
  local expire
  local now
  start=$(date +%s)
  expire=$((start + BE_PROBE_TIMEOUT))

  while true; do
    doris_note "Add myself($POD_HOST:$HEARTBEAT_PORT) to cluster as BACKEND(Compute Node)..."
    exec_sql "timeout 15 mysql --connect-timeout 2 -h $FE_SVC -P $FE_QUERY_PORT --skip-column-names --batch -e \"ALTER SYSTEM ADD BACKEND \"$POD_HOST:$HEARTBEAT_PORT\";\""

    # check if it was added successfully
    if show_backends | grep -q -w "$POD_HOST" &>/dev/null; then
      doris_note "Add myself to cluster successfully."
      break
    fi
    # check probe process timeout
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      doris_error "Add myself to cluster timed out."
    fi
    sleep BE_PROBE_INTERVAL
  done
}

# main process
if [[ -n $FE_SVC ]]; then
  doris_error "Missing environment variable FE_SVC for the FE service name"
fi

collect_env
ensure_node_role
add_self
doris_note "Ready to start BE(Compute Node)!"
start_be.sh
