#!/bin/bash
set -e

echoerr () { echo "$@" 1>&2; }

if [[ "$1" == "httpd-foreground" ]]; then
  shift

  # Attempt to set ServerLimit and MaxRequestWorkers based on the amount of
  # memory in the container. This will never use less than 16 servers, and
  # never more than 2000. If no memory limits are specified, then it will
  # use the lower, conservative defaults.
  ram_limit=$(</sys/fs/cgroup/memory/memory.limit_in_bytes)
  swp_limit=$(</sys/fs/cgroup/memory/memory.memsw.limit_in_bytes)
  exp_memory_size=${PIE_EXP_MEMORY_SIZE:-50}
  res_memory_size=${PIE_RES_MEMORY_SIZE:-50}

  echoerr "exp_memory_size: $exp_memory_size MB"
  echoerr "res_memory_size: $res_memory_size MB"
  echoerr "ram_limit: $ram_limit B"
  echoerr "swp_limit: $swp_limit B"

  APACHE_THREADS_PER_CHILD=25
  APACHE_SERVER_LIMIT=16

  if [[ "$ram_limit" != "9223372036854771712" && "$swp_limit" != "9223372036854771712" ]]; then
    ram_limit=$(echo "$ram_limit" | awk '{ print $1 / 1048576 }')
    swp_limit=$(echo "$swp_limit" | awk '{ print $1 / 1048576 }')

    APACHE_SERVER_LIMIT=$( \
      echo "$exp_memory_size $res_memory_size $ram_limit $swp_limit" \
      | awk '{ print int( ($3 + $4 - $2) / $1 ) }' \
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

  rm -f "$APACHE_PID_FILE"

  exec apache2 -DFOREGROUND -k start "$@"
else
  exec "$@"
fi
