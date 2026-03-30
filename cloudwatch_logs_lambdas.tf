module "cloudwatch_log_processor_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name                     = "${var.name_prefix}-cloudwatch-log-processor"
  description                       = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.description
  handler                           = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.handler
  runtime                           = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.runtime
  timeout                           = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.timeout
  memory_size                       = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.memory_size
  cloudwatch_logs_retention_in_days = var.cloudwatch_logs_max_retention_days


  source_path = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.path

  environment_variables = var.cloudwatch_logs_lambda_config.cloudwatch_log_processor.environment_variables

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.cloudwatch_log_processor_policy.json

  tags = var.tags
}

# Lambda permission to allow CloudWatch Logs to invoke the function
resource "aws_lambda_permission" "allow_cloudwatch_logs" {
  statement_id   = "AllowExecutionFromCloudWatchLogs"
  action         = "lambda:InvokeFunction"
  function_name  = module.cloudwatch_log_processor_lambda.lambda_function_name
  principal      = "logs.amazonaws.com"
  source_account = var.account_id
}

# IAM Policy for Log Processor Lambda
data "aws_iam_policy_document" "cloudwatch_log_processor_policy" {
  # S3 permissions to write logs
  statement {
    sid = "S3WriteAccess"
    actions = [
      "s3:Get*"
    ]
    resources = [
      "${module.s3_access_logs.s3_bucket_arn}/*",
      "${module.s3_waf_access_logs.s3_bucket_arn}/*"
    ]
  }

  statement {
    sid = "S3BucketAccess"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      module.s3_cloudwatch_logs[0].s3_bucket_arn
    ]
  }

  # CloudWatch Logs permissions for Lambda's own logging
  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-cloudwatch-log-processor:*"
    ]
  }
}

###############################################
# Lambda Function: Subscription Filter Manager
###############################################

module "subscription_filter_manager_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name                     = "${var.name_prefix}-subscription-filter-manager"
  description                       = var.cloudwatch_logs_lambda_config.subscription_filter_manager.description
  handler                           = var.cloudwatch_logs_lambda_config.subscription_filter_manager.handler
  runtime                           = var.cloudwatch_logs_lambda_config.subscription_filter_manager.runtime
  timeout                           = var.cloudwatch_logs_lambda_config.subscription_filter_manager.timeout
  memory_size                       = var.cloudwatch_logs_lambda_config.subscription_filter_manager.memory_size
  cloudwatch_logs_retention_in_days = var.cloudwatch_logs_max_retention_days

  source_path = var.cloudwatch_logs_lambda_config.subscription_filter_manager.path

  environment_variables = var.cloudwatch_logs_lambda_config.subscription_filter_manager.environment_variables

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.subscription_filter_manager_policy.json

  tags = var.tags
}

# IAM Policy for Subscription Filter Manager Lambda
data "aws_iam_policy_document" "subscription_filter_manager_policy" {
  # CloudWatch Logs permissions to manage subscription filters and retention
  statement {
    sid = "CloudWatchLogsManagement"
    actions = [
      "logs:DescribeLogGroups",
      "logs:DescribeSubscriptionFilters",
      "logs:PutSubscriptionFilter",
      "logs:DeleteSubscriptionFilter",
      "logs:PutRetentionPolicy"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:*"
    ]
  }

  # Lambda permissions to invoke the log processor
  statement {
    sid = "LambdaInvokeAccess"
    actions = [
      "lambda:GetFunction",
      "lambda:InvokeFunction"
    ]
    resources = [
      module.cloudwatch_log_processor_lambda.lambda_function_arn
    ]
  }

  # CloudWatch Logs permissions for Lambda's own logging
  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-subscription-filter-manager:*"
    ]
  }
}

###############################################
# EventBridge Rule to trigger Subscription Filter Manager
###############################################

resource "aws_cloudwatch_event_rule" "subscription_filter_manager_schedule" {
  name                = "${var.name_prefix}-subscription-filter-manager-schedule"
  description         = "Triggers subscription filter manager Lambda every 10 minutes"
  schedule_expression = "rate(10 minutes)"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "subscription_filter_manager_target" {
  rule      = aws_cloudwatch_event_rule.subscription_filter_manager_schedule.name
  target_id = "SubscriptionFilterManagerLambda"
  arn       = module.subscription_filter_manager_lambda.lambda_function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.subscription_filter_manager_lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.subscription_filter_manager_schedule.arn
}



# Promtail Lambda
module "lambda_promtail" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name                     = "${var.name_prefix}-lambda-promtail"
  description                       = var.cloudwatch_logs_lambda_config.lambda_promtail.description
  handler                           = var.cloudwatch_logs_lambda_config.lambda_promtail.handler
  runtime                           = var.cloudwatch_logs_lambda_config.lambda_promtail.runtime
  timeout                           = var.cloudwatch_logs_lambda_config.lambda_promtail.timeout
  memory_size                       = var.cloudwatch_logs_lambda_config.lambda_promtail.memory_size
  cloudwatch_logs_retention_in_days = var.cloudwatch_logs_max_retention_days

  architectures = ["arm64"]

  create_package        = false
  local_existing_package = var.cloudwatch_logs_lambda_config.lambda_promtail.path

  environment_variables = var.cloudwatch_logs_lambda_config.lambda_promtail.environment_variables

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [module.sg_lambda_promtail.security_group_id]

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.cloudwatch_log_processor_policy.json

  tags = var.tags
}


# S3 Bucket Notification to trigger Lambda Promtail for access logs
resource "aws_s3_bucket_notification" "access_logs_notification" {
  bucket = module.s3_access_logs.s3_bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_promtail.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".gz"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_promtail_access_logs]
}

# S3 Bucket Notification to trigger Lambda Promtail for WAF logs
resource "aws_s3_bucket_notification" "waf_logs_notification" {
  bucket = module.s3_waf_access_logs.s3_bucket_id

  lambda_function {
    lambda_function_arn = module.lambda_promtail.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".gz"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_promtail_waf_logs]
}

# Lambda permission to allow S3 access logs bucket to invoke the Promtail function
resource "aws_lambda_permission" "allow_s3_invoke_promtail_access_logs" {
  statement_id  = "AllowExecutionFromS3AccessLogs"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_promtail.lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_access_logs.s3_bucket_arn
}

# Lambda permission to allow S3 WAF logs bucket to invoke the Promtail function
resource "aws_lambda_permission" "allow_s3_invoke_promtail_waf_logs" {
  statement_id  = "AllowExecutionFromS3WafLogs"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_promtail.lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_waf_access_logs.s3_bucket_arn
}

module "sg_lambda_promtail" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name_prefix}-lambda-promtail"
  description = "Security group for Lambda Promtail"
  vpc_id      = module.vpc.vpc_id

  # ingress
  ingress_cidr_blocks = [var.vpc_cidr]
  ingress_rules       = ["all-all"]


  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-all"]
}

###############################################
# CloudWatch Loki Shipper Lambda
###############################################

module "cloudwatch_loki_shipper_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 7.0"

  function_name                     = "${var.name_prefix}-cloudwatch-loki-shipper"
  description                       = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.description
  handler                           = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.handler
  runtime                           = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.runtime
  timeout                           = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.timeout
  memory_size                       = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.memory_size
  cloudwatch_logs_retention_in_days = var.cloudwatch_logs_max_retention_days

  source_path = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.path

  vpc_subnet_ids         = module.vpc.private_subnets
  vpc_security_group_ids = [module.sg_lambda_promtail.security_group_id]

  environment_variables = var.cloudwatch_logs_lambda_config.cloudwatch_loki_shipper.environment_variables


  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.cloudwatch_loki_shipper_policy.json

  tags = var.tags
}

# IAM policy for CloudWatch Loki Shipper Lambda
data "aws_iam_policy_document" "cloudwatch_loki_shipper_policy" {
  # S3 permissions to read from CloudWatch logs bucket
  statement {
    sid = "S3ReadAccess"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      module.s3_cloudwatch_logs[0].s3_bucket_arn,
      "${module.s3_cloudwatch_logs[0].s3_bucket_arn}/*"
    ]
  }

  # CloudWatch Logs permissions for Lambda's own logging
  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-cloudwatch-loki-shipper:*"
    ]
  }
}

# S3 Bucket Notification to trigger CloudWatch Loki Shipper
resource "aws_s3_bucket_notification" "cloudwatch_logs_loki_notification" {
  bucket = module.s3_cloudwatch_logs[0].s3_bucket_id

  lambda_function {
    lambda_function_arn = module.cloudwatch_loki_shipper_lambda.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".gz"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_loki_shipper]
}

# Lambda permission to allow S3 to invoke the Loki Shipper function
resource "aws_lambda_permission" "allow_s3_invoke_loki_shipper" {
  statement_id  = "AllowExecutionFromS3CloudWatchLogs"
  action        = "lambda:InvokeFunction"
  function_name = module.cloudwatch_loki_shipper_lambda.lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_cloudwatch_logs[0].s3_bucket_arn
}
