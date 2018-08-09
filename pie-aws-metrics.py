#!/usr/bin/env python3
import boto3
from collections import defaultdict
import json
import logging
import os
import re
import requests
import socket
import time

logger = logging.getLogger(__name__)

logs_clnt = boto3.client('logs')

APACHE_STATUSLINE_RE = re.compile(r'^(?P<key>[^:]+):\s+(?P<value>.+)$')
ECS_TASKID_RE = re.compile(r'^.+:task/(?P<id>.+)$')

AGENT_HOST = os.environ.get('APACHE_AWS_AGENT_HOST', 'localhost:8008')
ECS_CONTAINER_METADATA_FILE = os.environ.get('ECS_CONTAINER_METADATA_FILE', None)
METRICS_LOGGROUP_NAME = os.environ['APACHE_AWS_METRICS_LOGGROUP_NAME']
METRICS_LOGSTREAM_NAME = os.environ.get('APACHE_AWS_METRICS_LOGSTREAM_NAME', None)
METRICS_RATE = int(os.environ.get('APACHE_AWS_METRICS_RATE', '300'))

class ApacheServer(object):
    """ Gathers and tracks the status of an Apache host. """
    def __init__(self, name='default', status_urlpath='/status'):
        self._name = name
        self._uptime = -1
        self._status_urlpath = status_urlpath
        self._status_prev = defaultdict(lambda: 0)

    def __str__(self):
        return self._name

    @property
    def name(self):
        return self._name

    def fetch_status(self):
        url = 'http://{0}{1}?auto'.format(AGENT_HOST, self._status_urlpath)
        r = requests.get(url, timeout=10)
        r.raise_for_status()

        result = {}
        r.encoding = 'ISO-8859-1'
        for line in r.text.splitlines():
            m = APACHE_STATUSLINE_RE.match(line.strip())
            if not m:
                continue

            key = m.group('key')
            value = m.group('value')
            if key in ('Scoreboard',):
                continue

            try:
                value = int(value)
            except ValueError:
                try:
                    value = float(value)
                except ValueError:
                    pass
            result[key] = value

        if result.get('Uptime', 0) < self._uptime:
            # Apache was restarted; clear our previous values
            self._status_prev = defaultdict(lambda: 0)
            self._uptime = result['Uptime']

        self._status_curr = defaultdict(lambda: 0)
        for key in ('Accesses', 'kBytes'):
            total_key = 'Total ' + key
            delta_key = 'Delta ' + key

            self._status_curr[total_key] = result.get(total_key, 0)
            result[delta_key] = self._status_curr[total_key] - self._status_prev[total_key]

        return result

    def update_status(self):
        if not self._status_curr:
            raise ValueError('current status values are invalid')
        self._status_prev = self._status_curr
        self._status_curr = defaultdict(lambda: 0)


def get_ecs_metadata():
    """
    Gets the ECS metadata for the container. This requires the
    ECS_CONTAINER_METADATA_FILE environment variable be defined or
    an exception will be thrown.
    """
    if not ECS_CONTAINER_METADATA_FILE:
        raise ValueError('No ECS_CONTAINER_METADATA_FILE')

    metadata_ready = False
    metadata = None
    while not metadata_ready:
        try:
            with open(ECS_CONTAINER_METADATA_FILE, 'r') as f:
                metadata = json.load(f)
        except Exception:
            logger.exception('Unable to open and parse %(file)', {
                'file': ECS_CONTAINER_METADATA_FILE,
            })
        else:
            metadata_ready = metadata.get('MetadataFileStatus', '') == 'READY'

        if not metadata_ready:
            logger.info('Waiting for ECS metadata')
            time.sleep(1)

    result = {
        'cluster':          metadata.get('Cluster', ''),
        'taskArn':          metadata.get('TaskARN', ''),
        'containerName':    metadata.get('ContainerName', ''),
    }
    m = ECS_TASKID_RE.match(result['taskArn'])
    if m:
        result['taskId'] = m.group('id')
    if result['containerName'] and result.get('taskId', None):
        result['containerId'] = '{0}/{1}'.format(result['containerName'], result['taskId'])

    return result


def get_logstream_seqtoken(logstream_name):
    while True:
        try:
            response = logs_clnt.describe_log_streams(
                logGroupName=METRICS_LOGGROUP_NAME,
                logStreamNamePrefix=logstream_name,
                orderBy='LogStreamName',
            )

            # Try to find out logstream in the returned values
            for logstream in response.get('logStreams', []):
                if logstream.get('logStreamName') == logstream_name:
                    return logstream.get('uploadSequenceToken', None)

            # We didn't find our logstream. Create it instead
            logs_clnt.create_log_stream(
                logGroupName=METRICS_LOGGROUP_NAME,
                logStreamName=logstream_name,
            )
            return None
        except Exception:
            logger.exception('Unable to get the sequence token for %(group)s:%(stream)s; will sleep and retry', {
                'group': METRICS_LOGGROUP_NAME,
                'stream': logstream_name,
            })

        time.sleep(10)


def process(server, logstream_name, logstream_seqtoken):
    events = {}
    try:
        logger.debug('Fetching status for %(name)s', {
            'name': server,
        })
        server_status = server.fetch_status()
        events[server.name] = {
            'timestamp': int(time.time()) * 1000,
            'message': json.dumps(server_status),
        }
    except Exception:
        logger.exception('Unable to fetch the status for %(server)s', {
            'server': server,
        })

    if not events:
        logger.warn('No events built')
        return logstream_seqtoken

    args = {
        'logGroupName':     METRICS_LOGGROUP_NAME,
        'logStreamName':    logstream_name,
        'logEvents':        list(events.values()),
    }
    if logstream_seqtoken:
        args['sequenceToken'] = logstream_seqtoken

    try:
        logger.debug('Sending events to %(group)s:%(stream)s', {
            'group': args['logGroupName'],
            'stream': args['logStreamName'],
        })
        response = logs_clnt.put_log_events(**args)
    except Exception:
        logger.exception('Unable to put log events')
        raise
    else:
        logstream_seqtoken = response.get('nextSequenceToken', None)
        server.update_status()

    return logstream_seqtoken

def run():
    logstream_name = METRICS_LOGSTREAM_NAME
    if not logstream_name:
        if ECS_CONTAINER_METADATA_FILE:
            logstream_name = get_ecs_metadata()['containerId']
        else:
            logstream_name = socket.gethostname()

    logstream_seqtoken = get_logstream_seqtoken(logstream_name)
    server = ApacheServer()

    while True:
        try:
            logstream_seqtoken = process(server, logstream_name, logstream_seqtoken)
        except Exception:
            logger.exception('Unable to process status metrics')
            logstream_seqtoken = get_logstream_seqtoken(logstream_name)

        time.sleep(METRICS_RATE)

if __name__ == '__main__':
    logging.basicConfig()
    run()
