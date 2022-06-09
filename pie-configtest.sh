#!/bin/bash
set -e

apache_defines=()
if [[ -f $APACHE_PID_FILE ]]; then
    apache_pid=$(cat "$APACHE_PID_FILE")
    readarray -t apache_defines < <(cat /proc/$apache_pid/cmdline | tr '\0' '\n' | sed -rne '/^-D/p')
fi

exec apache2ctl -t "${apache_defines[@]}"
