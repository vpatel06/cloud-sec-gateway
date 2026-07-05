import boto3
import json
import subprocess
from datetime import datetime

# Update this with your actual bucket name
BUCKET_NAME = 'wireguard-telemetry-vanij'

def get_wg_stats():
    try:
        # Get the stats from WireGuard
        return subprocess.check_output(['wg', 'show', 'wg0', 'dump'], text=True)
    except Exception as e:
        return f"Error gathering stats: {str(e)}"

def push_to_cloud():
    s3 = boto3.client('s3')
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    payload = {
        "timestamp": timestamp,
        "stats": get_wg_stats()
    }
    
    # Save to the cloud
    key = f"logs/status_{timestamp}.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=json.dumps(payload)
    )
    print(f"Telemetry data sent to S3 at {timestamp}")

if __name__ == "__main__":
    push_to_cloud()