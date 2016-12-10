#!/bin/bash
set -e

echoerr () { echo "$@" 1>&2; }

apache_envset () {
  # Attempt to set ServerLimit and MaxRequestWorkers based on the amount of
  # memory in the container. This will never use less than 16 servers, and
  # never more than 2000. If no memory limits are specified, then it will
  # use free space
  exp_memory_size=${PIE_EXP_MEMORY_SIZE:-50}
  res_memory_size=${PIE_RES_MEMORY_SIZE:-50}

  ram_limit=0
  if [[ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ]]; then
    ram_limit=$(</sys/fs/cgroup/memory/memory.limit_in_bytes)
    if [[ "$ram_limit" = "9223372036854771712" ]]; then
      ram_limit=0
    else
      ram_limit=$(echo "$ram_limit" | awk '{ print int( $1 / 1048576 ) }')
    fi
  fi
  (( ram_limit <= 0 )) && ram_limit=$(free -m | awk '/^Mem:/ { print $4 }')

  echoerr "exp_memory_size: $exp_memory_size MB"
  echoerr "res_memory_size: $res_memory_size MB"
  echoerr "ram_limit: $ram_limit MB"

  APACHE_THREADS_PER_CHILD=25
  APACHE_SERVER_LIMIT=16

  if (( ram_limit > 0 )); then
    APACHE_SERVER_LIMIT=$( \
      echo "$exp_memory_size $res_memory_size $ram_limit" \
      | awk '{ print int( ($3 - $2) / $1 ) }' \
    )
    if (( APACHE_SERVER_LIMIT < 16 )); then
      APACHE_SERVER_LIMIT=16
    elif (( APACHE_SERVER_LIMIT > 2000 )); then
      APACHE_SERVER_LIMIT=2000
    fi
  fi

  APACHE_MAX_REQUEST_WORKERS=$(( APACHE_SERVER_LIMIT * APACHE_THREADS_PER_CHILD ))

  echoerr "APACHE_SERVER_LIMIT: $APACHE_SERVER_LIMIT"
  echoerr "APACHE_THREADS_PER_CHILD: $APACHE_THREADS_PER_CHILD"
  echoerr "APACHE_MAX_REQUEST_WORKERS: $APACHE_MAX_REQUEST_WORKERS"

  export APACHE_THREADS_PER_CHILD APACHE_SERVER_LIMIT APACHE_MAX_REQUEST_WORKERS

  echoerr "DIR_SUFFIX: ${DIR_SUFFIX:=}"
	echoerr "APACHE_CONFDIR: ${APACHE_CONFDIR:=/etc/apache2}"
  if [[ -z "$APACHE_ENVVARS" ]]; then
    APACHE_ENVVARS=$APACHE_CONFDIR/envvars
  fi
  export APACHE_CONFDIR APACHE_ENVVARS

  # Read configuration variable file if it is present
  if [[ -f /etc/default/apache2$DIR_SUFFIX ]]; then
    . /etc/default/apache2$DIR_SUFFIX
  elif [[ -f /etc/default/apache2 ]]; then
    . /etc/default/apache2
  fi

  . $APACHE_ENVVARS
  export APACHE_RUN_USER=pie-www-data
  export APACHE_RUN_GROUP=pie-www-data
}

if [[ "$1" == "apache2-pie" ]]; then
  shift

  apache_envset

  rm -f "$APACHE_PID_FILE"
  exec apache2 -DFOREGROUND -DPIE "$@"
elif [[ "$1" == "apache2" ]]; then
  shift

  apache_envset

  rm -f "$APACHE_PID_FILE"
  exec apache2 -DFOREGROUND "$@"
elif [[ "$1" == "apache2"* ]]; then
  apache_envset
  exec "$@"
else
  exec "$@"
fi
