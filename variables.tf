variable "region" {
  description = "AWS region being deployed to"
  type        = string
}

variable "account_id" {
  description = "AWS account ID of the account being deployed to"
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to all resource names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

############################
# CloudWatch / OAM
############################

variable "monitoring_account_sink_name" {
  description = "Name of the OAM sink in the monitoring account"
  type        = string
  default     = ""
}

variable "source_account_ids" {
  description = "List of source account IDs allowed to link to the OAM sink"
  type        = list(string)
  default     = []
}

variable "monitoring_regions" {
  description = "List of regions to include in the centralised log rule"
  type        = list(string)
  default     = []
}

variable "monitoring_account_sink_identifier" {
  description = "ARN or ID of the OAM sink in the monitoring account (used in source accounts)"
  type        = string
  default     = ""
}

variable "monitoring_account_id" {
  description = "AWS account ID of the monitoring account (used in source accounts)"
  type        = string
  default     = ""
}

variable "cross_account_monitoring_managed_policy" {
  description = "List of IAM managed policy names to attach to the CloudWatch cross-account sharing role"
  type        = list(string)
  default     = []
}

############################
# Lambda
############################

variable "cloudwatch_logs_max_retention_days" {
  description = "CloudWatch Logs retention in days for all Lambda log groups"
  type        = number
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (used for Lambda security group ingress)"
  type        = string
}

variable "cloudwatch_logs_lambda_config" {
  description = "Configuration for each CloudWatch logs Lambda function"
  type = object({
    cloudwatch_log_processor = object({
      description           = string
      handler               = string
      runtime               = string
      timeout               = number
      memory_size           = number
      path                  = string
      environment_variables = map(string)
    })
    subscription_filter_manager = object({
      description           = string
      handler               = string
      runtime               = string
      timeout               = number
      memory_size           = number
      path                  = string
      environment_variables = map(string)
    })
    lambda_promtail = object({
      description           = string
      handler               = string
      runtime               = string
      timeout               = number
      memory_size           = number
      path                  = string
      environment_variables = map(string)
    })
    cloudwatch_loki_shipper = object({
      description           = string
      handler               = string
      runtime               = string
      timeout               = number
      memory_size           = number
      path                  = string
      environment_variables = map(string)
    })
  })
}
