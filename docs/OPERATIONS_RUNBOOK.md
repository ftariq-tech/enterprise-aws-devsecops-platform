# Operations and failure scenarios

| Scenario | Signal | Operator action |
|---|---|---|
| Invalid order | API HTTP 422 | Correct client request; do not retry unchanged |
| Authentication failure | API HTTP 401 | Check Secrets Manager reference and API caller token; never paste secrets in issues |
| Worker failures | Logs: `message_failed`, growing SQS age | Check logs, task health, IAM, SQS visibility, dependency latency |
| Poison message | DLQ visible count > 0 | Inspect synthetic payload safely; fix consumer; redrive after validation |
| Unexpected duplicates | Logs: `message_acked result=duplicate` | Normal under at-least-once delivery; verify processing/conditional write behavior |
| Failed ECS rollout | ECS deployment circuit breaker, service events | Inspect target group health, secret grants, startup logs, IAM and resource limits; roll back after assessing impact |
| Excess cloud cost | AWS Budgets and Cost Explorer | Reduce desired counts; disable runtime; tear down demo infrastructure |

**On-call checklist:** Verify incident scope → capture sanitized log timestamps and trace IDs (not secrets) → contain/recover → validate ALB/SQS/DynamoDB states → document root cause and corrective action.

**Sample SLO (design proposal only):** 99.9% API request availability, p95 acceptance latency under 500 ms, and 99% of valid demo messages processed within 60 seconds. These have NOT been measured; actual SLOs require load testing and metrics instrumentation.
