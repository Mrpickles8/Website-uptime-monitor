terraform {
  required_version = "1.16.5"
  cloud {
    organization = "Dominionorg"
    workspaces {
      name = "Website-uptime-monitoring"
    }
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


resource "aws_dynamodb_table" "uptime_results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "website_url"
  range_key = "timestamp"

  attribute {
    name = "website_url"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_rule" "monitor" {
  name                = "${var.project_name}-trigger"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.monitor.name
  arn  = aws_lambda_function.monitor.arn
}

resource "aws_lambda_permission" "eventbridge" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monitor.arn
}

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Action = "sts:AssumeRole"

        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]

        Resource = [
          aws_dynamodb_table.uptime_results.arn
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "sns:Publish"
        ]

        Resource = [
          aws_sns_topic.alerts.arn
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "logs:*"
        ]

        Resource = ["*"]
      }
    ]
  })
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "lambda_monitor.py"
  output_path = "lambda_monitor.zip"
}

resource "aws_lambda_function" "monitor" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${var.project_name}-checker"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_monitor.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.uptime_results.name
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
      THRESHOLD_MS   = tostring(var.response_time_threshold_ms)
      WEBSITES       = jsonencode(var.websites_to_monitor)
    }
  }
}

