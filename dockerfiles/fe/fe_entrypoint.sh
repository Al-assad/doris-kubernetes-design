#!/bin/bash

# Extra environment variables:
#  FE_SVC: FE service name, required.
#  AUTH_USER: account name to execute sql, optional, default: root
#  AUTH_PWD: account password to execute sql, optional.

source entrypoint_helper.sh

FE_CONF_FILE=${DORIS_HOME}/fe/conf/fe.conf

# pod fqdn host
declare POD_HOST
# pod index for k8s stateful set
declare POD_INDEX
# doris edit log port
declare EDIT_LOG_PORT
# doris query port
declare QUERY_PORT

# FE leader
declare FE_LEADER
# fe probe interval: 2 seconds
FE_PROBE_INTERVAL=2
# timeout for probe leader: 120 seconds
FE_PROBE_TIMEOUT=120

# force fqdn mode on
ensure_enable_fqdn() {
  inject_item_into_conf_file "$FE_CONF_FILE" 'enable_fqdn_mode' 'true'
}

show_frontends() {
  exec_sql "timeout 15 mysql --connect-timeout 2 -h $FE_SVC -P $QUERY_PORT --skip-column-names --batch -e 'show frontends;'"
}

# collect env info from container
collect_env() {
  POD_HOST=$(hostname -f)
  POD_INDEX=$(echo "$POD_HOST" | awk -F'.' '{print $1}' | awk -F'-' '{print $NF}')
  EDIT_LOG_PORT=$(get_value_from_conf_file "$FE_CONF_FILE" 'edit_log_port' 9010)
  QUERY_PORT=$(get_value_from_conf_file "$FE_CONF_FILE" 'query_port' 9030)
}

# probe fe leader
probe_leader() {
  if [[ $POD_INDEX == 0 ]]; then
    probe_leader_for_pod0
  else
    probe_leader_for_podx
  fi
}

probe_leader_for_pod0() {
  set +e
  local start
  local expire
  local members
  local leader
  local now

  start=$(date +%s)
  expire=$((start + FE_PROBE_TIMEOUT))

  while true; do
    members=$(show_frontends)
    leader=$(echo "$members" | grep '\<LEADER\>' | awk '{print $2}')

    # has leader
    if [[ -n $leader ]]; then
      doris_note "Find FE leader: $leader"
      FE_LEADER=$leader
      break
    fi

    # no leader yet
    doris_warn "No FE leader yet."
    # no member exists, declare myself as master FE
    if [[ -z $members ]]; then
      doris_note "Declare myself as master FE: $POD_HOST"
      FE_LEADER=""
      break
    fi
    # has other members, check if it is timeout
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      doris_error "Probe FE leader timed out."
    fi
    sleep $FE_PROBE_INTERVAL
  done
}

probe_leader_for_podx() {
  set +e
  local start
  local expire
  local leader
  local now

  start=$(date +%s)
  expire=$((start + FE_PROBE_TIMEOUT))

  while true; do
    leader=$(show_frontends | grep '\<LEADER\>' | awk '{print $2}')
    # has leader
    if [[ -n $leader ]]; then
      doris_note "Find FE leader: $leader"
      FE_LEADER=$leader
      break
    fi

    # no leader yet, check if it is timeout
    doris_warn "No FE leader yet."
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      doris_error "Probe FE leader timed out."
    fi
    sleep $FE_PROBE_INTERVAL
  done
}

# add myself to fe leader as follower
add_myself_to_leader() {
  set +e
  local start
  local expire
  local now
  start=$(date +%s)
  expire=$((start + FE_PROBE_TIMEOUT))

  while true; do
    doris_note "Add myself($POD_HOST:$EDIT_LOG_PORT) to FE leader($FE_LEADER:$EDIT_LOG_PORT) as follower..."
    exec_sql "mysql --connect-timeout 2 -h $FE_SVC -P $QUERY_PORT --skip-column-names --batch -e \"ALTER SYSTEM ADD FOLLOWER \"$POD_HOST:$EDIT_LOG_PORT\";\""

    # check if it was added successfully
    if show_frontends | grep -q -w "$MYSELF" &>/dev/null; then
      doris_note "Add myself to FE leader successfully."
      break
    fi
    # check probe process timeout
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      doris_error "Add myself to FE leader timed out."
    fi
    sleep FE_PROBE_INTERVAL
  done
}

# main process
if [[ -n $FE_SVC ]]; then
  doris_error "Missing environment variable FE_SVC for the FE service name"
fi

if [[ -f ${DORIS_HOME}/fe/meta/image/ROLE ]]; then
  # start fe with meta role exist.
  doris_note "Start FE with role meta exits."
  ensure_enable_fqdn
  start_fe.sh
else
  # start fe with meta role does not exist
  doris_note "Meta role does not exist, FE starts for the first time."
  opts=""
  collect_env
  probe_leader
  # fe leader exists
  if [[ -n $FE_LEADER ]]; then
    opts+=" --helper $FE_LEADER:$EDIT_LOG_PORT"
    add_myself_to_leader
  fi
  ensure_enable_fqdn
  start_fe.sh "$opts"
fi