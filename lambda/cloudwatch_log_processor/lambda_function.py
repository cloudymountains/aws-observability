"""
CloudWatch Log Processor
This Lambda function receives CloudWatch logs via subscription filters,
processes them, and stores them to S3 bucket.
"""

import json
import gzip
import base64
import os
import boto3
from datetime import datetime
from botocore.exceptions import ClientError

# Initialize AWS clients
s3_client = boto3.client('s3')

# Environment variables
S3_BUCKET_NAME = os.environ['S3_BUCKET_NAME']
S3_PREFIX = os.environ.get('S3_PREFIX', 'cloudwatch')


def lambda_handler(event, context):
    """
    Main handler function that processes CloudWatch logs and stores them to S3.
    """
    print(f"Received event with {len(event.get('Records', []))} records")
    
    try:
        # CloudWatch Logs data is base64 encoded and gzipped
        compressed_payload = base64.b64decode(event['awslogs']['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_data = json.loads(uncompressed_payload)
        
        print(f"Processing logs from log group: {log_data['logGroup']}")
        print(f"Log stream: {log_data['logStream']}")
        print(f"Number of log events: {len(log_data['logEvents'])}")
        
        # Process and store logs
        store_logs_to_s3(log_data)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Logs processed successfully',
                'logGroup': log_data['logGroup'],
                'logStream': log_data['logStream'],
                'eventCount': len(log_data['logEvents'])
            })
        }
        
    except Exception as e:
        print(f"Error processing logs: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def store_logs_to_s3(log_data):
    """
    Store processed logs to S3 bucket with organized structure.
    """
    try:
        # Extract log group and stream information
        log_group = log_data['logGroup']
        log_stream = log_data['logStream']
        log_events = log_data['logEvents']
        
        # Clean log group name for S3 path (remove leading slashes and special chars)
        clean_log_group = log_group.lstrip('/').replace('/', '-')
        
        # Generate timestamp for partitioning
        now = datetime.utcnow()
        year = now.strftime('%Y')
        month = now.strftime('%m')
        day = now.strftime('%d')
        hour = now.strftime('%H')
        
        # Create S3 key with partitioning structure
        # Format: {prefix}/{log-group}/year=YYYY/month=MM/day=DD/hour=HH/{timestamp}-{stream}.json.gz
        timestamp = now.strftime('%Y%m%d-%H%M%S-%f')
        clean_stream = log_stream.replace('/', '-').replace('$', '')
        
        s3_key = f"{S3_PREFIX}/{clean_log_group}/year={year}/month={month}/day={day}/hour={hour}/{timestamp}-{clean_stream}.json.gz"
        
        # Prepare log data for storage
        log_content = {
            'logGroup': log_group,
            'logStream': log_stream,
            'owner': log_data.get('owner'),
            'subscriptionFilters': log_data.get('subscriptionFilters', []),
            'messageType': log_data.get('messageType'),
            'logEvents': log_events,
            'metadata': {
                'processedAt': now.isoformat(),
                'eventCount': len(log_events)
            }
        }
        
        # Convert to JSON and compress
        json_content = json.dumps(log_content, default=str)
        compressed_content = gzip.compress(json_content.encode('utf-8'))
        
        # Upload to S3
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=compressed_content,
            ContentType='application/json',
            ContentEncoding='gzip',
            ServerSideEncryption='AES256',
            Metadata={
                'log-group': log_group,
                'log-stream': log_stream,
                'event-count': str(len(log_events))
            }
        )
        
        print(f"Successfully stored logs to s3://{S3_BUCKET_NAME}/{s3_key}")
        print(f"Compressed size: {len(compressed_content)} bytes")
        
    except ClientError as e:
        print(f"Error storing logs to S3: {str(e)}")
        raise
    except Exception as e:
        print(f"Unexpected error in store_logs_to_s3: {str(e)}")
        raise


def format_log_event(event):
    """
    Format a single log event for better readability.
    """
    return {
        'timestamp': datetime.fromtimestamp(event['timestamp'] / 1000.0).isoformat(),
        'message': event['message'],
        'id': event.get('id')
    }

