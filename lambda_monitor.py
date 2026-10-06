import boto3
import json
import os
import time
import urllib.request
from datetime import datetime, timezone


dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")


def check_website(url, threshold_ms):
    result = {
        "url": url,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "status": "OK",
        "http_code": 0,
        "response_time_ms": 0,
        "error": None,
    }

    try:
        start = time.time()

        req = urllib.request.urlopen(url, timeout=10)

        result["response_time_ms"] = int((time.time() - start) * 1000)
        result["http_code"] = req.getcode()

        if req.getcode() != 200:
            result["status"] = "ERROR"
            result["error"] = f"HTTP {req.getcode()}"

        elif result["response_time_ms"] > threshold_ms:
            result["status"] = "SLOW"
            result["error"] = (
                f'Response time {result["response_time_ms"]}ms '
                f"> {threshold_ms}ms"
            )

    except Exception as e:
        result["status"] = "DOWN"
        result["error"] = str(e)

    return result


def lambda_handler(event, context):
    table = dynamodb.Table(os.environ["DYNAMODB_TABLE"])

    topic_arn = os.environ["SNS_TOPIC_ARN"]

    threshold = int(
        os.environ.get("THRESHOLD_MS", "3000")
    )

    websites = json.loads(
        os.environ["WEBSITES"]
    )

    for url in websites:
        result = check_website(url, threshold)

        table.put_item(
            Item={
                "website_url": url,
                "timestamp": result["timestamp"],
                "status": result["status"],
                "http_code": result["http_code"],
                "response_time_ms": result["response_time_ms"],
                "error": result["error"] or "None",
            }
        )

        if result["status"] != "OK":
            sns.publish(
                TopicArn=topic_arn,
                Subject=f'ALERT: {result["status"]} - {url}',
                Message=(
                    f"Website: {url}\n"
                    f'Status: {result["status"]}\n'
                    f'Error: {result["error"]}\n'
                    f'Time: {result["timestamp"]}'
                ),
            )

    return {
        "statusCode": 200,
        "monitored": len(websites),
    }
