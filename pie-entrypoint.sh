#!/bin/bash
set -e

echoerr () { echo "$@" 1>&2; }

apache_envset () {
  echoerr "APACHE_CACHE_LOCK: ${APACHE_CACHE_LOCK:=on}"
  echoerr "APACHE_CACHE_QUICK_HANDLER: ${APACHE_CACHE_QUICK_HANDLER:=off}"
  echoerr "APACHE_CACHE_DEFAULT: ${APACHE_CACHE_DEFAULT:=3600}"
  echoerr "APACHE_CACHE_MIN: ${APACHE_CACHE_MIN:=0}"
  echoerr "APACHE_CACHE_MAX: ${APACHE_CACHE_MAX:=86400}"
  echoerr "APACHE_CACHE_LIMIT: ${APACHE_CACHE_LIMIT}"
  echoerr "APACHE_CACHE_IGNORE_CACHECONTROL: ${APACHE_CACHE_IGNORE_CACHECONTROL:=on}"
  echoerr "APACHE_CACHE_IGNORE_NOLASTMOD: ${APACHE_CACHE_IGNORE_NOLASTMOD:=on}"
  echoerr "APACHE_CACHE_IGNORE_QUERYSTRING: ${APACHE_CACHE_IGNORE_QUERYSTRING:=off}"
  echoerr "APACHE_CACHE_STORE_EXPIRED: ${APACHE_CACHE_STORE_EXPIRED:=off}"
  echoerr "APACHE_CACHE_STORE_NOSTORE: ${APACHE_CACHE_STORE_NOSTORE:=off}"
  echoerr "APACHE_CACHE_STORE_PRIVATE: ${APACHE_CACHE_STORE_PRIVATE:=off}"
  export APACHE_CACHE_LOCK APACHE_CACHE_QUICK_HANDLER APACHE_CACHE_DEFAULT APACHE_CACHE_MIN APACHE_CACHE_MAX APACHE_CACHE_LIMIT
  export APACHE_CACHE_IGNORE_CACHECONTROL APACHE_CACHE_IGNORE_NOLASTMOD APACHE_CACHE_IGNORE_QUERYSTRING
  export APACHE_CACHE_STORE_EXPIRED APACHE_CACHE_STORE_NOSTORE APACHE_CACHE_STORE_PRIVATE

  echoerr "APACHE_PROXY_URL: ${APACHE_PROXY_URL}"
  echoerr "APACHE_PROXY_PRESERVE_HOST: ${APACHE_PROXY_PRESERVE_HOST:=off}"
  export APACHE_PROXY_URL APACHE_PROXY_PRESERVE_HOST

  echoerr "APACHE_SERVER_NAME (provided): ${APACHE_SERVER_NAME}"
  if [[ -z $APACHE_SERVER_NAME ]]; then
      if [[ -n $HOSTNAME ]]; then
          # Take just the first entry returned from getent ahosts
          hostname_ent=($(getent ahosts "$HOSTNAME" | egrep ' STREAM ' | head -n1))
          if [[ ${#hostname_ent[*]} -gt 0 ]]; then
              hostname_revent=($(getent ahosts "${hostname_ent[0]}" | egrep ' STREAM ' | head -n1))

              if [[ ${#hostname_revent[*]} -gt 0 && ${hostname_revent[2]} == *"."* ]]; then
                  echoerr "ServerName: using $HOSTNAME reverse lookup"
                  APACHE_SERVER_NAME="${hostname_revent[2]}"
              elif [[ $HOSTNAME == *"."* ]]; then
                  echoerr "ServerName: using $HOSTNAME"
                  APACHE_SERVER_NAME="$HOSTNAME"
              else
                  echoerr "ServerName: using $HOSTNAME host entry IP"
                  APACHE_SERVER_NAME="${hostname_ent[0]}"
              fi
          else
              echoerr "ServerName: unable to get the host entry for $HOSTNAME"
          fi
      fi
      echoerr "APACHE_SERVER_NAME (calculated): ${APACHE_SERVER_NAME:=127.0.0.1}"
  fi
  export APACHE_SERVER_NAME

  echoerr "APACHE_SERVER_LIMIT (provided): ${APACHE_SERVER_LIMIT:=0}"

  if (( APACHE_SERVER_LIMIT <= 0 )); then
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
    (( ram_limit <= 0 )) && ram_limit=$(free -m | awk '/^Mem:/ { print $4 + $6 + $7 }')

    echoerr "exp_memory_size: $exp_memory_size MB"
    echoerr "res_memory_size: $res_memory_size MB"
    echoerr "ram_limit: $ram_limit MB"

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

    echoerr "APACHE_SERVER_LIMIT (calculated): $APACHE_SERVER_LIMIT"
  fi

  APACHE_THREADS_PER_CHILD=25
  APACHE_MAX_REQUEST_WORKERS=$(( APACHE_SERVER_LIMIT * APACHE_THREADS_PER_CHILD ))

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
  echoerr "APACHE_PID_FILE: ${APACHE_PID_FILE:=/var/run/apache2/apache2.pid}"
  export APACHE_PID_FILE
  export APACHE_RUN_USER=pie-www-data
  export APACHE_RUN_GROUP=pie-www-data

  touch "/etc/apache2/trusted-proxies.list"
}

apache_cacheinit () {
    chown $APACHE_RUN_USER:$APACHE_RUN_GROUP /var/cache/apache2/mod_cache_disk

    if [[ -n $APACHE_CACHE_LIMIT ]]; then
        set +e
        htcacheclean -n -i -d60 -p/var/cache/apache2/mod_cache_disk -l${APACHE_CACHE_LIMIT}
        set -e
    fi
}

apache_loginit () {
  echoerr "APACHE_LOGGING=${APACHE_LOGGING}"

  chown $APACHE_RUN_USER:$APACHE_RUN_GROUP /var/log/shibboleth-www
  chmod 0750 /var/log/shibboleth-www

  for f in /var/log/apache2/{access,ssl_request}.log /var/log/shibboleth-www/native.log; do
    case "$APACHE_LOGGING" in
      pipe)
        [[ -e $f && ! -p $f ]] && rm -- "$f"

        if [[ ! -e $f ]]; then
            mkfifo -m 0640 "$f"
        else
            chmod 0640 "$f"
        fi

        if [[ $f == *"/shibboleth-www/"* ]]; then
          chown $APACHE_RUN_USER:$APACHE_RUN_GROUP "$f"
        else
          chown root:adm "$f"
        fi
        ;;

      file)
        [[ -e $f && ! -f $f ]] && rm -- "$f"
        touch "$f"
        chmod 0640 "$f"
        if [[ $f == *"/shibboleth-www/"* ]]; then
          chown $APACHE_RUN_USER:$APACHE_RUN_GROUP "$f"
        else
          chown root:adm "$f"
        fi
        ;;

      *)
        [[ -e $f && ! -L $f ]] && rm -- "$f"

        if [[ ! -e $f ]]; then
            ln -s /proc/self/fd/2 "$f"
        fi
        ;;
    esac
  done
}

if [[ "$1" == "apache2-pie" ]]; then
  shift

  apache_envset
  apache_cacheinit
  apache_loginit
  set +e
  pie-trustedproxies.sh 1>&2
  if [[ -n $APACHE_AWS_METRICS_LOGGROUP_NAME ]]; then
    setsid pie-aws-metrics.py 1>&2 &
  fi
  set -e

  rm -f "$APACHE_PID_FILE"
  exec apache2 -DFOREGROUND -DPIE "$@"
elif [[ "$1" == "apache2" ]]; then
  shift

  apache_envset
  apache_cacheinit
  apache_loginit
  set +e
  pie-trustedproxies.sh 1>&2
  if [[ -n $APACHE_AWS_METRICS_LOGGROUP_NAME ]]; then
    setsid pie-aws-metrics.py 1>&2 &
  fi
  set -e

  rm -f "$APACHE_PID_FILE"
  exec apache2 -DFOREGROUND "$@"
elif [[ "$1" == "apache2"* || "$1" == "pie-configtest.sh" ]]; then
  apache_envset
  exec "$@"
else
  exec "$@"
fi
