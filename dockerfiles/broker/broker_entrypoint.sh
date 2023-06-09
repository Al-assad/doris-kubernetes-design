#!/bin/bash

# Extra environment variables:
#  FE_SVC: FE service name, required.
#  FE_QUERY_PORT: FE service query port, optional, default: 9030
#  ACC_USER: account name to execute sql, optional, default: k8sopr
#  ACC_PWD: account password to execute sql, optional.

source entrypoint_helper.sh

BROKER_CONF_FILE=${DORIS_HOME}/broker/conf/apache_hdfs_broker.conf

# self fqdn host
declare SELF_HOST
# doris fe query port
declare FE_QUERY_PORT
# doris broker ipc port
declare BROKER_IPC_PORT

# broker probe interval: 2 seconds
PROBE_INTERVAL=2
# timeout for probing broker: 60 seconds
PROBE_TIMEOUT=60

# collect env info from container
collect_env() {
  SELF_HOST=$(hostname -f)
  BROKER_IPC_PORT=$(get_value_from_conf_file "$BROKER_CONF_FILE" 'broker_ipc_port' 8000)
  if [[ -z $FE_QUERY_PORT ]]; then
    FE_QUERY_PORT=9030
  fi
}

show_brokers() {
  timeout 15 mysql --connect-timeout 2 -h "$FE_SVC" -P "$FE_QUERY_PORT" -u"$ACC_USER" -p"$ACC_PWD" --skip-column-names --batch -e 'SHOW BROKER;'
}

# add self to cluster
add_self() {
  set +e
  local start
  local expire
  local now
  start=$(date +%s)
  expire=$((start + PROBE_TIMEOUT))

  while true; do
    doris_note "Add myself($SELF_HOST:$BROKER_IPC_PORT) to cluster as BROKER..."
    timeout 15 mysql --connect-timeout 2 -h "$FE_SVC" -P "$FE_QUERY_PORT" -u"$ACC_USER" -p"$ACC_PWD" --skip-column-names --batch -e "ALTER SYSTEM ADD BROKER \"$SELF_HOST:$BROKER_IPC_PORT\";"

    # check if it was added successfully
    if show_brokers | grep -q -w "$SELF_HOST" &>/dev/null; then
      doris_note "Add myself to cluster successfully."
      break
    fi
    # check probe process timeout
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      doris_error "Add myself to cluster timed out."
    fi
    sleep $PROBE_INTERVAL
  done
}

# main process
if [[ -n $FE_SVC ]]; then
  doris_error "Missing environment variable FE_SVC for the FE service name"
fi

collect_env
add_self
doris_note "Ready to start Broker!"
start_broker.sh
