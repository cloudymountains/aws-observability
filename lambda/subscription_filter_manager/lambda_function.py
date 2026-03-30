"""
CloudWatch Logs Subscription Filter Manager
This Lambda function runs every 10 minutes and creates subscription filters
for all CloudWatch log groups to forward logs to the log processor Lambda.
"""

import json
import os
import boto3
from botocore.exceptions import ClientError

# Initialize AWS clients
logs_client = boto3.client('logs')
lambda_client = boto3.client('lambda')

# Environment variables
LOG_PROCESSOR_LAMBDA_ARN = os.environ['LOG_PROCESSOR_LAMBDA_ARN']
FILTER_NAME = os.environ.get('FILTER_NAME', 'cloudwatch-to-s3-filter')
FILTER_PATTERN = os.environ.get('FILTER_PATTERN', '')  # Empty string means all logs
SKIP_PATTERNS = os.environ.get('SKIP_PATTERNS', '')  # Comma-separated list of patterns to skip
MAX_RETENTION_DAYS = int(os.environ.get('MAX_RETENTION_DAYS', '7'))  # Maximum retention period in days


def lambda_handler(event, context):
    """
    Main handler function that manages subscription filters for all log groups.
    """
    print(f"Starting subscription filter management")
    print(f"Log Processor Lambda ARN: {LOG_PROCESSOR_LAMBDA_ARN}")
    
    stats = {
        'total_log_groups': 0,
        'filters_created': 0,
        'filters_already_exist': 0,
        'retention_updated': 0,
        'retention_already_ok': 0,
        'errors': 0
    }
    
    try:
        # Get all log groups
        log_groups = get_all_log_groups()
        stats['total_log_groups'] = len(log_groups)
        
        print(f"Found {len(log_groups)} log groups")
        
        # Process each log group
        for log_group in log_groups:
            log_group_name = log_group['logGroupName']
            
            # Skip the log groups for our own Lambda functions to avoid circular logging
            if should_skip_log_group(log_group_name):
                print(f"Skipping log group: {log_group_name}")
                continue
            
            try:
                # Check and update retention period if needed
                retention_result = check_and_update_retention(log_group_name, log_group)
                if retention_result == 'updated':
                    stats['retention_updated'] += 1
                elif retention_result == 'ok':
                    stats['retention_already_ok'] += 1

                # Check if subscription filter already exists
                if subscription_filter_exists(log_group_name):
                    print(f"Subscription filter already exists for: {log_group_name}")
                    stats['filters_already_exist'] += 1
                else:
                    # Create subscription filter
                    create_subscription_filter(log_group_name)
                    print(f"Created subscription filter for: {log_group_name}")
                    stats['filters_created'] += 1

            except Exception as e:
                print(f"Error processing log group {log_group_name}: {str(e)}")
                stats['errors'] += 1
        
        print(f"Subscription filter management completed. Stats: {json.dumps(stats)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(stats)
        }
        
    except Exception as e:
        print(f"Fatal error in subscription filter management: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


def get_all_log_groups():
    """
    Retrieve all CloudWatch log groups using pagination.
    """
    log_groups = []
    next_token = None
    
    while True:
        try:
            if next_token:
                response = logs_client.describe_log_groups(nextToken=next_token)
            else:
                response = logs_client.describe_log_groups()
            
            log_groups.extend(response.get('logGroups', []))
            next_token = response.get('nextToken')
            
            if not next_token:
                break
                
        except ClientError as e:
            print(f"Error retrieving log groups: {str(e)}")
            raise
    
    return log_groups


def check_and_update_retention(log_group_name, log_group_info):
    """
    Check if log group retention period exceeds MAX_RETENTION_DAYS and update if needed.
    Returns: 'updated' if retention was changed, 'ok' if already within limits, 'none' if no retention set
    """
    current_retention = log_group_info.get('retentionInDays')

    # If no retention is set (None), logs are kept indefinitely
    # We should set it to MAX_RETENTION_DAYS
    if current_retention is None:
        try:
            logs_client.put_retention_policy(
                logGroupName=log_group_name,
                retentionInDays=MAX_RETENTION_DAYS
            )
            print(f"Set retention to {MAX_RETENTION_DAYS} days for: {log_group_name} (was: Never Expire)")
            return 'updated'
        except ClientError as e:
            print(f"Error setting retention for {log_group_name}: {str(e)}")
            raise

    # If retention is greater than MAX_RETENTION_DAYS, update it
    if current_retention > MAX_RETENTION_DAYS:
        try:
            logs_client.put_retention_policy(
                logGroupName=log_group_name,
                retentionInDays=MAX_RETENTION_DAYS
            )
            print(f"Updated retention to {MAX_RETENTION_DAYS} days for: {log_group_name} (was: {current_retention} days)")
            return 'updated'
        except ClientError as e:
            print(f"Error updating retention for {log_group_name}: {str(e)}")
            raise

    # Retention is already within acceptable limits
    return 'ok'


def should_skip_log_group(log_group_name):
    """
    Determine if a log group should be skipped.
    Skip patterns are provided via SKIP_PATTERNS environment variable as comma-separated values.
    """
    # Parse skip patterns from environment variable
    if SKIP_PATTERNS:
        skip_patterns = [pattern.strip() for pattern in SKIP_PATTERNS.split(',') if pattern.strip()]
    else:
        # Default patterns if none provided
        skip_patterns = [
            '/aws/lambda/subscription-filter-manager',
            '/aws/lambda/cloudwatch-log-processor'
        ]

    for pattern in skip_patterns:
        if pattern in log_group_name:
            return True

    return False


def subscription_filter_exists(log_group_name):
    """
    Check if a subscription filter already exists for the log group.
    """
    try:
        response = logs_client.describe_subscription_filters(
            logGroupName=log_group_name,
            filterNamePrefix=FILTER_NAME
        )
        
        # Check if our specific filter exists
        for filter_info in response.get('subscriptionFilters', []):
            if filter_info['filterName'] == FILTER_NAME:
                return True
        
        return False
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            return False
        raise


def create_subscription_filter(log_group_name):
    """
    Create a subscription filter for the specified log group.
    """
    try:
        logs_client.put_subscription_filter(
            logGroupName=log_group_name,
            filterName=FILTER_NAME,
            filterPattern=FILTER_PATTERN,
            destinationArn=LOG_PROCESSOR_LAMBDA_ARN
        )
    except ClientError as e:
        print(f"Error creating subscription filter for {log_group_name}: {str(e)}")
        raise

