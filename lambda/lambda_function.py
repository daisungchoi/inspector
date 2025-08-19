import boto3, os, datetime, json

sns = boto3.client("sns")
inspector = boto3.client("inspector2")

def lambda_handler(event, context):
    findings = inspector.list_findings(
        maxResults=10 # adjust
    )

    report = {
        "timestamp": str(datetime.datetime.utcnow()),
        "findingCount": len(findings.get("findings", [])),
        "findings": findings.get("findings", [])
    }

    sns.publish(
        TopicArn=os.environ["SNS_TOPIC_ARN"],
        Subject="AWS Inspector Weekly Report",
        Message=json.dumps(report, indent=2)
    )

    return {"status": "ok"}
