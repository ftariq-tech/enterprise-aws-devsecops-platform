# Security scope and reporting

This is a **demonstration project**, not a security-certified production application. Never commit AWS credentials, tokens, real customer records or Terraform state. Use synthetic inputs.

Demo controls: private ECS tasks, TLS at load balancer, token required in AWS mode, scoped task roles, GitHub OIDC for releases, conditional DynamoDB writes, non-root container user, GitHub CI tests/static scan, SQS dead-letter queue.

Not implemented: per-user authorization, per-tenant separation, WAF, production rate limits, end-to-end tracing, immutable artifact provenance, centralized identity, encrypted remote Terraform backend, thorough pentesting. External side effects would require an outbox/replay strategy beyond the demo write idempotency.

Report security concerns privately rather than exposing credentials in GitHub Issues. Revoke any inadvertently leaked credentials immediately through the provider's security process.
