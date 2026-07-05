import json
import boto3
import os

def lambda_handler(event, context):
    """
    Processes WireGuard telemetry files uploaded to S3.
    """
    # 1. Log the trigger for debugging/observability
    print("--- LAMBDA WAS TRIGGERED ---")
    
    # 2. Extract bucket and file info from the S3 event
    try:
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = event['Records'][0]['s3']['object']['key']
        print(f"Analyzing {key}...")
    except KeyError as e:
        print(f"Error parsing S3 event: {e}")
        return {'statusCode': 400, 'body': 'Invalid S3 event'}

    # 3. Retrieve the file from S3
    s3 = boto3.client('s3')
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        data = json.loads(content)
        
        # 4. Output the telemetry data to CloudWatch Logs
        print(f"Data received: {data}")
        
    except Exception as e:
        print(f"Error reading file from S3: {e}")
        return {'statusCode': 500, 'body': 'Error processing file'}

    return {
        'statusCode': 200,
        'body': json.dumps('Telemetry processed successfully')
    }