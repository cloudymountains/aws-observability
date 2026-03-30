"""
CloudWatch Loki Shipper Lambda Function

This Lambda function is triggered by S3 events when CloudWatch logs are exported to S3.
It reads the log files, extracts the log group name from the S3 key, and ships the logs
to Grafana Loki with the log group name as a label.
"""

import gzip
import json
import os
import re
from datetime import datetime
from io import BytesIO
from urllib.parse import unquote_plus

import boto3
import requests

# Environment variables
LOKI_URL = os.environ.get('LOKI_URL')  # e.g., https://loki.example.com/loki/api/v1/push
LOKI_USERNAME = os.environ.get('LOKI_USERNAME', '')
LOKI_PASSWORD = os.environ.get('LOKI_PASSWORD', '')
LOKI_BEARER_TOKEN = os.environ.get('LOKI_BEARER_TOKEN', '')
LOKI_TENANT_ID = os.environ.get('LOKI_TENANT_ID', '')
EXTRA_LABELS = os.environ.get('EXTRA_LABELS', '{}')  # JSON string of additional labels
BATCH_SIZE = int(os.environ.get('BATCH_SIZE', '1000'))  # Number of log lines per batch

# Initialize AWS clients
s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Main Lambda handler function triggered by S3 events.
    """
    print(f"Received event: {json.dumps(event)}")

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])

        print(f"Processing file: s3://{bucket}/{key}")

        try:
            # Extract log group name from S3 key
            log_group_name = extract_log_group_name(key)
            print(f"Extracted log group name: {log_group_name}")

            # Download and decompress the log file
            log_data = download_and_decompress(bucket, key)

            # Parse CloudWatch Logs export format
            log_events = parse_cloudwatch_logs(log_data)

            # Ship logs to Loki
            ship_to_loki(log_events, log_group_name)

            print(f"Successfully processed {len(log_events)} log events from {key}")

        except Exception as e:
            print(f"Error processing {key}: {str(e)}")
            raise

    return {
        'statusCode': 200,
        'body': json.dumps('Successfully processed CloudWatch logs')
    }


def extract_log_group_name(s3_key):
    """
    Extract the CloudWatch log group name from the S3 key.
    Expected S3 key format: <prefix>/<log-group-name>/year=YYYY/month=MM/day=DD/hour=HH/<file>.gz
    Example: cloudwatch-logs/aws-lambda-my-function/year=2024/month=12/day=25/hour=14/file.json.gz
    """
    # Remove the prefix and extract the log group name
    # The log group name is between the first '/' and '/year='
    match = re.search(r'^[^/]+/([^/]+)/year=', s3_key)
    if match:
        return match.group(1)

    # Fallback: try to extract from the path before year=
    parts = s3_key.split('/year=')
    if len(parts) > 1:
        path_parts = parts[0].split('/')
        if len(path_parts) >= 2:
            return path_parts[-1]

    # If we can't extract it, use the first part of the path
    return s3_key.split('/')[0] if '/' in s3_key else 'unknown'


def download_and_decompress(bucket, key):
    """
    Download a file from S3 and decompress it if it's gzipped.
    """
    response = s3_client.get_object(Bucket=bucket, Key=key)
    body = response['Body'].read()

    # Check if the file is gzipped
    if key.endswith('.gz'):
        with gzip.GzipFile(fileobj=BytesIO(body)) as gz:
            return gz.read().decode('utf-8')
    else:
        return body.decode('utf-8')


def parse_cloudwatch_logs(log_data):
    """
    Parse CloudWatch Logs export format.
    The export format is JSON with log events.
    """
    log_events = []

    for line in log_data.strip().split('\n'):
        if not line:
            continue

        try:
            log_entry = json.loads(line)

            # Handle different CloudWatch export formats
            if 'logEvents' in log_entry:
                # Format: {"logEvents": [...], "logGroup": "...", "logStream": "..."}
                for event in log_entry['logEvents']:
                    log_events.append({
                        'timestamp': event.get('timestamp'),
                        'message': event.get('message', ''),
                        'log_stream': log_entry.get('logStream', '')
                    })
            elif 'timestamp' in log_entry and 'message' in log_entry:
                # Format: {"timestamp": ..., "message": "..."}
                log_events.append({
                    'timestamp': log_entry.get('timestamp'),
                    'message': log_entry.get('message', ''),
                    'log_stream': log_entry.get('logStream', '')
                })
            else:
                # Treat the entire line as a message
                log_events.append({
                    'timestamp': int(datetime.now().timestamp() * 1000),
                    'message': line,
                    'log_stream': ''
                })

        except json.JSONDecodeError:
            # If it's not JSON, treat it as a plain text log line
            log_events.append({
                'timestamp': int(datetime.now().timestamp() * 1000),
                'message': line,
                'log_stream': ''
            })

    return log_events


def ship_to_loki(log_events, log_group_name):
    """
    Ship log events to Grafana Loki.
    """
    if not log_events:
        print("No log events to ship")
        return

    if not LOKI_URL:
        print("LOKI_URL not configured, skipping log shipping")
        return

    # Parse extra labels
    try:
        extra_labels = json.loads(EXTRA_LABELS)
    except json.JSONDecodeError:
        print(f"Invalid EXTRA_LABELS JSON: {EXTRA_LABELS}")
        extra_labels = {}

    # Build base labels
    labels = {
        'job': 'cloudwatch',
        'log_group': log_group_name.replace('/', '_').replace('-', '_'),
        **extra_labels
    }

    # Process logs in batches
    for i in range(0, len(log_events), BATCH_SIZE):
        batch = log_events[i:i + BATCH_SIZE]
        send_batch_to_loki(batch, labels)


def send_batch_to_loki(log_events, base_labels):
    """
    Send a batch of log events to Loki.
    """
    # Group logs by log stream
    streams = {}
    for event in log_events:
        log_stream = event.get('log_stream', 'unknown')
        if log_stream not in streams:
            streams[log_stream] = []
        streams[log_stream].append(event)

    # Build Loki push request
    loki_streams = []
    for log_stream, events in streams.items():
        # Create labels for this stream
        stream_name = log_stream.replace('/', '_').replace('-', '_') if log_stream else 'unknown'
        stream_labels = {
            **base_labels,
            'log_stream': stream_name
        }

        # Build values array: [[timestamp_ns, log_line], ...]
        values = []
        for event in events:
            # Convert milliseconds to nanoseconds
            timestamp_ns = str(event['timestamp'] * 1000000)
            message = event['message']
            values.append([timestamp_ns, message])

        loki_streams.append({
            'stream': stream_labels,
            'values': values
        })

    # Build the request payload
    payload = {
        'streams': loki_streams
    }

    # Prepare headers
    headers = {
        'Content-Type': 'application/json'
    }

    # Add authentication
    auth = None
    if LOKI_BEARER_TOKEN:
        headers['Authorization'] = f'Bearer {LOKI_BEARER_TOKEN}'
    elif LOKI_USERNAME and LOKI_PASSWORD:
        auth = (LOKI_USERNAME, LOKI_PASSWORD)

    # Add tenant ID if configured (for multi-tenant Loki)
    if LOKI_TENANT_ID:
        headers['X-Scope-OrgID'] = LOKI_TENANT_ID

    # Send to Loki
    try:
        print(f"Sending {len(log_events)} log events to Loki ({len(loki_streams)} streams)")
        response = requests.post(
            LOKI_URL,
            json=payload,
            headers=headers,
            auth=auth,
            timeout=30
        )
        response.raise_for_status()
        print(f"Successfully sent logs to Loki: {response.status_code}")
    except requests.exceptions.RequestException as e:
        print(f"Error sending logs to Loki: {str(e)}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response status: {e.response.status_code}")
            print(f"Response body: {e.response.text}")
        raise

