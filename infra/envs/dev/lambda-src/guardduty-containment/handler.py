import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    detail = event.get("detail", {})
    finding_type = detail.get("type", "unknown")
    severity = detail.get("severity", "unknown")
    finding_id = detail.get("id", "unknown")
    account_id = detail.get("accountId", "unknown")
    region = event.get("region", "unknown")

    logger.warning(
        "High-severity GuardDuty finding received: id=%s type=%s severity=%s account=%s region=%s",
        finding_id,
        finding_type,
        severity,
        account_id,
        region,
    )

    # Safe first version: observe/log only.
    # Later containment actions can be added here after testing.

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "handled": True,
                "finding_id": finding_id,
                "finding_type": finding_type,
                "severity": severity,
            }
        ),
    }
