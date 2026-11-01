# aws-observability

Terraform and Lambda functions for centralizing CloudWatch metrics and logs from many AWS accounts into one monitoring account, and shipping the logs to Grafana Loki.

The setup is described step by step in the series [Centralized AWS Observability](https://cloudymountains.cloud/projects/observability/):

- [Part 1: the architecture](https://cloudymountains.cloud/projects/observability/aws-observability-part-one/), with why Grafana, Prometheus, YACE and the LGTM stack
- [Part 2: OAM and Terraform](https://cloudymountains.cloud/projects/observability/aws-observability-part-two/), covering the code in this repository

## What's here

| Path | What it does |
|---|---|
| `cloudwatch.tf` | CloudWatch cross-account observability: the OAM sink and sink policy in the monitoring account (also in `us-east-1`), the OAM link in source accounts, the cross-account sharing role, and an organization-wide CloudWatch Logs centralization rule |
| `cloudwatch_logs_lambdas.tf` | The Lambda functions below, their IAM policies, the EventBridge schedule and the S3 notifications that trigger them |
| `variables.tf` | Inputs: region and account IDs, the OAM sink name or identifier, source account IDs and regions |
| `lambda/subscription_filter_manager/` | Runs every 10 minutes and adds a subscription filter to every log group that lacks one, so new log groups are picked up without anyone remembering to wire them; it also caps log retention |
| `lambda/cloudwatch_log_processor/` | Receives log events from the subscription filters and stores them in S3 |
| `lambda/cloudwatch_loki_shipper/` | Triggered by new log files in S3; ships them to Loki with the log group name as a label |
| `lambda/lambda_promtail/` | [lambda-promtail](https://github.com/grafana/lambda-promtail) for ALB/CloudFront access logs and WAF logs landing in S3 |

## Using it

This is reference code from a working setup rather than a published module. It has no provider or backend configuration, and it references resources from the surrounding root module that are not in this repository: the S3 bucket modules (`module.s3_access_logs`, `module.s3_waf_access_logs`, `module.s3_cloudwatch_logs`), the `aws.us-east-1` provider alias and `data.aws_caller_identity.current`. Copy the parts you need into your own root module.

The OAM sink and link are regional: create them in every region whose metrics you want centralized, in both the monitoring and the source accounts.
