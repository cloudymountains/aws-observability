#### Monitoring account
resource "aws_oam_sink" "this" {
  name = var.monitoring_account_sink_name
}

resource "aws_oam_sink_policy" "this" {
  sink_identifier = aws_oam_sink.this.id

  // See https://docs.aws.amazon.com/OAM/latest/APIReference/API_PutSinkPolicy.html for examples
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["oam:CreateLink", "oam:UpdateLink"]
        Effect   = "Allow"
        Resource = "*"
        Principal = {
          "AWS" = var.source_account_ids
        }
        Condition = {
          "ForAllValues:StringEquals" = {
            "oam:ResourceTypes" = ["AWS::CloudWatch::Metric"]
          }
        }
      }
    ]
  })
}

# Log rule in the monitoring account
resource "aws_observabilityadmin_centralization_rule_for_organization" "this" {
  rule_name = "aggragated-logs-rule"

  rule {
    destination {
      region  = var.region
      account = data.aws_caller_identity.current.account_id
      destination_logs_configuration {
        logs_encryption_configuration {
          encryption_strategy = "AWS_OWNED"
        }
      }
    }

    source {
      regions = var.monitoring_regions
      scope   = "OrganizationId = '${data.aws_organizations_organization.current.id}'"

      source_logs_configuration {
        encrypted_log_group_strategy = "ALLOW"
        log_group_selection_criteria = "*"
      }
    }
  }
  tags = var.tags
}

#### Monitoring account for North Virginia
resource "aws_oam_sink" "virginia" {
  provider = aws.us-east-1
  name     = var.monitoring_account_sink_name
}

resource "aws_oam_sink_policy" "virginia" {
  provider        = aws.us-east-1
  sink_identifier = aws_oam_sink.virginia.id

  // See https://docs.aws.amazon.com/OAM/latest/APIReference/API_PutSinkPolicy.html for examples
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["oam:CreateLink", "oam:UpdateLink"]
        Effect   = "Allow"
        Resource = "*"
        Principal = {
          "AWS" = var.source_account_ids
        }
        Condition = {
          "ForAllValues:StringEquals" = {
            "oam:ResourceTypes" = ["AWS::CloudWatch::Metric"]
          }
        }
      }
    ]
  })
}

# ##### Monitoring account for Oregon
# resource "aws_oam_sink" "oregon" {
#   count    = var.source_account_ids != [] ? 1 : 0
#   provider = aws.oregon
#   name     = var.monitoring_account_sink_name
# }

# resource "aws_oam_sink_policy" "oregon" {
#   count           = var.source_account_ids != [] ? 1 : 0
#   provider        = aws.oregon
#   sink_identifier = aws_oam_sink.oregon[0].id

#   // See https://docs.aws.amazon.com/OAM/latest/APIReference/API_PutSinkPolicy.html for examples
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action   = ["oam:CreateLink", "oam:UpdateLink"]
#         Effect   = "Allow"
#         Resource = "*"
#         Principal = {
#           "AWS" = var.source_account_ids
#         }
#         Condition = {
#           "ForAllValues:StringEquals" = {
#             "oam:ResourceTypes" = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup"]
#           }
#         }
#       }
#     ]
#   })
# }

#### Source accounts

resource "aws_oam_link" "this" {
  label_template  = "$AccountName"
  resource_types  = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup"]
  sink_identifier = var.monitoring_account_sink_identifier
}


resource "aws_iam_role" "cloudwatch-cross-account-observability" {
  name = "CloudWatch-CrossAccountSharingRole"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "AWS" : var.monitoring_account_id
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "policy" {
  for_each = var.monitoring_account_sink_identifier != "" ? toset(var.cross_account_monitoring_managed_policy) : []

  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
  role       = aws_iam_role.cloudwatch-cross-account-observability.name
}
