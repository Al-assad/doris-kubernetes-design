#!/bin/bash

# Extra environment variables:
#  FE_SVC: FE service name, required.
#  ACC_USER: account name to execute sql, optional.
#  ACC_PWD: account password to execute sql, optional.

source entrypoint_helper.sh

FE_CONF_FILE=${DORIS_HOME}/fe/conf/fe.conf

# self fqdn host
declare SELF_HOST
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
# timeout for probe leader: 60 seconds
FE_PROBE_TIMEOUT=60

# force fqdn mode on
ensure_enable_fqdn() {
  inject_item_into_conf_file "$FE_CONF_FILE" 'enable_fqdn_mode' 'true'
}

show_frontends() {
  timeout 15 mysql --connect-timeout 2 -h "$FE_SVC" -P "$QUERY_PORT" -u"$ACC_USER" -p"$ACC_PWD" --skip-column-names --batch -e 'SHOW FRONTENDS;'
}

# collect env info from container
collect_env() {
  SELF_HOST=$(myself_host)
  POD_INDEX=$(echo "$SELF_HOST" | awk -F'.' '{print $1}' | awk -F'-' '{print $NF}')
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
      doris_note "Declare myself as master FE: $SELF_HOST"
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

# add self to fe leader as follower
add_self() {
  set +e
  local start
  local expire
  local now
  start=$(date +%s)
  expire=$((start + FE_PROBE_TIMEOUT))

  while true; do
    doris_note "Add myself($SELF_HOST:$EDIT_LOG_PORT) to FE leader($FE_LEADER:$EDIT_LOG_PORT) as FOLLOWER..."
    timeout 15 mysql --connect-timeout 2 -h "$FE_SVC" -P "$QUERY_PORT" -u"$ACC_USER" -p"$ACC_PWD" --skip-column-names --batch -e "ALTER SYSTEM ADD FOLLOWER \"$SELF_HOST:$EDIT_LOG_PORT\";"

    # check if it was added successfully
    if show_frontends | grep -q -w "$SELF_HOST" &>/dev/null; then
      doris_note "Add myself to cluster successfully."
      break
    fi
    # check probe process timeout
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      doris_error "Add myself to FE leader timed out."
    fi
    sleep $FE_PROBE_INTERVAL
  done
}

# create account for internal node operation.
# user: $ACC_USER, password: $ACC_PWD, role: NODE_PRIV, ADMIN_PRIV
create_opr_account() {
  set +e
  local start
  local expire
  local now
  start=$(date +%s)
  expire=$((start + FE_PROBE_TIMEOUT))

  while true; do
    doris_note "Create doris user($ACC_USER) for internal node operation..."
    timeout 15 mysql --connect-timeout 2 -h "$SELF_HOST" -P "$QUERY_PORT" -uroot --skip-column-names --batch -e "CREATE USER $ACC_USER IDENTIFIED BY '$ACC_PWD'; GRANT NODE_PRIV, ADMIN_PRIV ON RESOURCE * TO '$ACC_USER';"

    # check if user was created successfully
    if show_grants | grep -q -w "$ACC_USER" &>/dev/null; then
      doris_note "Create user($ACC_USER) with role(NODE_PRIV, ADMIN_PRIV) successfully."
      break
    fi
    # check probe process timeout
    now=$(date +%s)
    if [[ $expire -le $now ]]; then
      rm -f "${DORIS_HOME}"/fe/meta/image/ROLE
      doris_error "Create user($ACC_USER) with role(NODE_PRIV, ADMIN_PRIV) timed out."
    fi
    sleep $FE_PROBE_INTERVAL
  done
}

show_grants() {
  timeout 15 mysql --connect-timeout 2 -h "$FE_SVC" -P "$QUERY_PORT" -uroot --skip-column-names --batch -e 'SHOW ALL GRANTS;'
}

# main process
if [[ -n $FE_SVC ]]; then
  doris_error "Missing environment variable FE_SVC for the FE service name"
fi

if [[ -f ${DORIS_HOME}/fe/meta/image/ROLE ]]; then
  # start fe with meta role exist.
  doris_note "Start FE with role meta exits."
  ensure_enable_fqdn
  doris_note "Ready to start FE!"
  start_fe.sh
else
  # start fe with meta role does not exist
  doris_note "Meta role does not exist, FE starts for the first time."
  opts=""
  collect_env
  ensure_enable_fqdn
  probe_leader
  if [[ -n $FE_LEADER ]]; then
    # fe leader exists
    opts+=" --helper $FE_LEADER:$EDIT_LOG_PORT"
    add_self
    doris_note "Ready to start FE!"
    start_fe.sh "$opts"
  else
    # fe leader no exits, starts as master FE
    doris_note "Ready to start FE as Master!"
    start_fe.sh "$opts" &
    create_opr_account
    fg %1
  fi
fi
