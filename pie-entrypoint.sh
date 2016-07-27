#!/bin/bash
set -e

if [[ "$1" == "httpd-foreground" ]]; then
  shift

  # Attempt to set ServerLimit and MaxRequestWorkers based on the amount of
  # free memory in the container. This will never use less than 16 servers, and
  # never more than 2000.
  exp_memory_size=${PIE_EXP_MEMORY_SIZE:-50}
  free_memory=$(free -mt | awk '/^Total:/ { print $4 }')

  APACHE_THREADS_PER_CHILD=25
  >&2 echo "APACHE_THREADS_PER_CHILD: $APACHE_THREADS_PER_CHILD"

  APACHE_SERVER_LIMIT=$(echo "$exp_memory_size $free_memory" | awk '{ print int( $2 / $1 ) - 1 }')
  if (( APACHE_SERVER_LIMIT < 16 )); then
    APACHE_SERVER_LIMIT=16
  elif (( APACHE_SERVER_LIMIT > 2000 )); then
    APACHE_SERVER_LIMIT=2000
  fi
  >&2 echo "APACHE_SERVER_LIMIT: $APACHE_SERVER_LIMIT"

  APACHE_MAX_REQUEST_WORKERS=$(( APACHE_SERVER_LIMIT * APACHE_THREADS_PER_CHILD ))
  >&2 echo "APACHE_MAX_REQUEST_WORKERS: $APACHE_MAX_REQUEST_WORKERS"

  export APACHE_THREADS_PER_CHILD APACHE_SERVER_LIMIT APACHE_MAX_REQUEST_WORKERS

  >&2 echo "DIR_SUFFIX: ${DIR_SUFFIX:=}"
	>&2 echo "APACHE_CONFDIR: ${APACHE_CONFDIR:=/etc/apache2}"
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
