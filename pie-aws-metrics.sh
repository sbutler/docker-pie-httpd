#!/bin/bash
# Copyright (c) 2018 University of Illinois Board of Trustees
# All rights reserved.
#
# Developed by: 		Technology Services
#                      	University of Illinois at Urbana-Champaign
#                       https://techservices.illinois.edu/
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# with the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
#	* Redistributions of source code must retain the above copyright notice,
#	  this list of conditions and the following disclaimers.
#	* Redistributions in binary form must reproduce the above copyright notice,
#	  this list of conditions and the following disclaimers in the
#	  documentation and/or other materials provided with the distribution.
#	* Neither the names of Technology Services, University of Illinois at
#	  Urbana-Champaign, nor the names of its contributors may be used to
#	  endorse or promote products derived from this Software without specific
#	  prior written permission.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH
# THE SOFTWARE.
set -e

echoerr () { echo "$@" 1>&2; }

aws_metadata() {
    while [[ "$(jq -r '.MetadataFileStatus' < "$ECS_CONTAINER_METADATA_FILE")" != "READY" ]]; do
        echo "Waiting for metadata file to be ready"
        sleep 1
    done

    ecs_cluster="$(jq -r '.Cluster' < "$ECS_CONTAINER_METADATA_FILE")"
    ecs_taskarn="$(jq -r '.TaskARN' < "$ECS_CONTAINER_METADATA_FILE")"
    ecs_taskid="${ecs_taskarn##*:task/}"
    ecs_containername="$(jq -r '.ContainerName' < "$ECS_CONTAINER_METADATA_FILE")"
    ecs_containerid="${ecs_containername}/${ecs_taskid}"
}

apache_process() {
    local logstream_seqtoken='' logstream="$(
        aws logs describe-log-streams \
            --log-group-name "$APACHE_AWS_METRICS_LOGGROUP_NAME" \
            --log-stream-name-prefix "$APACHE_AWS_METRICS_LOGSTREAM_NAME" \
            --max-items 1 \
            --query "logStreams[?logStreamName == '$APACHE_AWS_METRICS_LOGSTREAM_NAME'] | [0]"
        )"
    if [[ -n $logstream ]]; then
        logstream_seqtoken="$(jq -r '.uploadSequenceToken' <<< "$logstream")"
    else
        aws logs create-log-stream --log-group-name "$APACHE_AWS_METRICS_LOGGROUP_NAME" --log-stream-name "$APACHE_AWS_METRICS_LOGSTREAM_NAME"
    fi

    declare -A prev_counters=(["Total Accesses"]=0 ["Total kBytes"]=0)
    local msgfile="$(mktemp /tmp/pie-aws-metrics.msg.XXXXXX.json)"
    local evtfile="$(mktemp /tmp/pie-aws-metrics.evt.XXXXXX.json)"

    local log_result t
    while : ; do
        t="$(date '+%s')000"

        { curl --fail --max-time 10 --silent "http://${APACHE_AWS_AGENT_HOST}/status?auto" || true; } | while read line; do
            k="${line%%: *}"
            v="${line##*: }"

            [[ $k != "Scoreboard" ]] && printf '%s\0%s\0' "$k" "$v"
            case "$k" in
                "Total Accesses")
                    printf '%s\0%d\0' Accesses $(( v - prev_counters["Total Accesses"] ))
                    ;;

                "Total kBytes")
                    printf '%s\0%d\0' kBytes $(( v - prev_counters["Total kBytes"] ))
                    ;;
            esac
        done | jq -Rs '
                    split("\u0000")
                    | . as $a
                    | reduce range(0; length/2) as $i
                        ({}; . + {($a[2*$i]): ($a[2*$i + 1]|fromjson? // .)})' > "$msgfile"

        jq -n \
            --argjson t $t \
            --slurpfile m "$msgfile" \
            '[ { timestamp: $t, message: $m|first|tojson } ]' > "$evtfile"

        set +e
        log_result="$(aws logs put-log-events \
            --log-group-name "$APACHE_AWS_METRICS_LOGGROUP_NAME" \
            --log-stream-name "$APACHE_AWS_METRICS_LOGSTREAM_NAME" \
            --log-events "file://$evtfile" \
            --sequence-token "$logstream_seqtoken"
        )"
        set -e
        if [[ $? -eq 0 ]]; then
            # Can't set variables in a loop as part of a pipe; do it here
            prev_counters["Total Accesses"]="$(jq -r '.["Total Accesses"]' "$msgfile")"
            prev_counters["Total kBytes"]="$(jq -r '.["Total kBytes"]' "$msgfile")"
            logstream_seqtoken="$(jq -r '.nextSequenceToken' <<< "$log_result")"
        else
            # Something went wrong. Get the sequence token again
            echoerr "Failed putting log event"
            logstream_seqtoken="$(
                aws logs describe-log-streams \
                    --log-group-name "$APACHE_AWS_METRICS_LOGGROUP_NAME" \
                    --log-stream-name-prefix "$APACHE_AWS_METRICS_LOGSTREAM_NAME" \
                    --max-items 1 \
                    --query "logStreams[?logStreamName == '$APACHE_AWS_METRICS_LOGSTREAM_NAME'] | [0].uploadSequenceToken"
                )"
        fi

        sleep $APACHE_AWS_METRICS_RATE
    done

    rm -f -- "$msgfile" "$evtfile"
}

echo "APACHE_AWS_AGENT_HOST: ${APACHE_AWS_AGENT_HOST:=localhost:8080}"
echo "APACHE_AWS_METRICS_RATE: ${APACHE_AWS_METRICS_RATE:=300}"
echo "APACHE_AWS_METRICS_LOGGROUP_NAME: ${APACHE_AWS_METRICS_LOGGROUP_NAME:=$1}"
echo "APACHE_AWS_METRICS_LOGSTREAM_NAME: ${APACHE_AWS_METRICS_LOGSTREAM_NAME:=$2}"

if [[ -z $APACHE_AWS_METRICS_LOGGROUP ]]; then
    echoerr "You must specify a log group name."
    exit 1
fi

if [[ -z $APACHE_AWS_METRICS_LOGSTREAM_NAME ]]; then
    if [[ -z $ECS_CONTAINER_METADATA_FILE ]]; then
        APACHE_AWS_METRICS_LOGSTREAM_NAME="$(hostname)"
    else
        aws_metadata
        APACHE_AWS_METRICS_LOGSTREAM_NAME="$ecs_containerid"
    fi
fi

apache_process
