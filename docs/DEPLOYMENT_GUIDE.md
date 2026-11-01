# Optional, cost-bearing AWS deployment guide

**Do not deploy to AWS just to obtain a portfolio screenshot.** GitHub CI and local tests are sufficient to show verified engineering work. This guide is for an account you own or have explicit permission to use.

## Stage 0: prerequisites and charge assessment

- Review AWS pricing for **NAT Gateway (hourly plus data)**, **Application Load Balancer**, **ECS Fargate tasks**, ECR, SQS, DynamoDB, CloudWatch, and Secrets Manager. Terraform `enable_runtime=false` still creates a billable NAT Gateway and other resources.
- Install AWS CLI, Terraform >= 1.6, Docker, jq. Create a separate AWS demo environment with billing budget alerts and least-privilege user permissions.
- Have an AWS account you administer, a validated same-region ACM certificate and a secret in Secrets Manager for a **random API token**. Configure public DNS to the ALB after provisioning runtime. Do not share token in commits or logs.
- Do not use real customer data. Make sure secret is retrieved via task **execution role**, not committed to `.tfvars` or GitHub.

## Stage 1: infrastructure foundations

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Review settings, current AWS account identity, region and estimated charges.
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=demo.tfplan
# terraform apply demo.tfplan  # OPTIONAL; incurs AWS charges
```

Default `enable_runtime=false` does not start ECS services or ALB; it DOES create VPC, NAT Gateway, SQS, DynamoDB, ECR, IAM, ECS cluster, and CloudWatch resources. Treat this as infrastructure to destroy after the demo.

## Stage 2: image, credentials, runtime

1. Build and push a container image with a unique immutable tag (for example `sha-<12-char-commit-sha>`) into the ECR repository. The CI workflow only builds locally; it never pushes to AWS.
2. Create the API token as a **Secrets Manager secret** in the AWS Console. Create an ACM certificate in the same region as ALB and validate ownership of a DNS name. Certificate and secret ARNs should be supplied via ignored `terraform.tfvars` or secure environment variables.
3. Update `image_tag`, `acm_certificate_arn`, `api_token_secret_arn`, and `enable_runtime=true`, then review `terraform plan`. The guard fails if placeholders remain.
4. Optionally set `enable_github_deploy_role=true`; `create_github_oidc_provider=true` only if your AWS account does not already have a GitHub OIDC provider. GitHub environment `production` should require human approval. The exact repo in `github_repository` must match GitHub `owner/repo`.
5. After successful deployment, verify ALB HTTPS with the correct DNS hostname/certificate and X-API-Key; send a synthetic request and verify queue consumption, DynamoDB state, and CloudWatch logs. Never advertise testing that has not occurred.
6. Configure GitHub environment variables: `AWS_REGION`, `AWS_ACCOUNT_ID`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_API_SERVICE`, `ECS_WORKER_SERVICE`; put deploy role ARN in environment secret `AWS_DEPLOY_ROLE_ARN`. Do not permit unreviewed release dispatches.

## Stage 3: cleanup

Check persistent state file is present and backed up before running `terraform destroy`; do not delete state prematurely. Confirm ECS, ALB, NAT Gateway/EIP, queues, DB and logs are gone and billing alerts remain active. If ECR contains images, remove them deliberately before destroy (repository is set not to force delete). DNS/ACM/secret created separately must be managed separately.

## Production gaps (intentional)

- One NAT gateway is cheaper but not highly available across AZs.
- API uses a simple token, not OAuth/JWT, quotas, gateway-based rate limiting, or WAF.
- Outbound ECS access uses NAT and broadly permits TCP 443; production should use VPC endpoints and tighter destination controls.
- DLQ CloudWatch alarm has **no delivery destination**; add SNS/on-call integration.
- CI uses build + static scans; production requires dependency pinning, SBOM, provenance/signature, image vulnerability policy, backup restore tests, load tests, application metrics and dedicated security reviews.
- SQS delivers at least once. DynamoDB conditional insert makes the **demo DB write** idempotent; external business side effects would need stronger transactional semantics and recovery strategy.
- Terraform state is local in the demo; production should use encrypted remote state with locking, audit controls and separate environments.
