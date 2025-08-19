provider "aws" {
  region = "us-east-1"
}

# 1. Enable Inspector v2
resource "aws_inspector2_enabler" "this" {
  account_ids = ["724585721064"] # AWS Account ID
  resource_types = ["EC2", "ECR", "LAMBDA"]
}

# 2. SNS topic for notifications
resource "aws_sns_topic" "inspector_reports" {
  name = "inspector-weekly-report"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.inspector_reports.arn
  protocol  = "email"
  endpoint  = "dchoi@aft.org" # Email
}

# 3. Lambda IAM role
resource "aws_iam_role" "lambda_role" {
  name = "inspector-report-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "inspector_read" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonInspector2ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "sns_publish" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
}

# 4. Lambda function (Python)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "inspector_report" {
  function_name = "inspector-weekly-report"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.11"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.inspector_reports.arn
    }
  }
}

# 5. EventBridge rule - weekly (Sunday 00:00 UTC)
resource "aws_cloudwatch_event_rule" "weekly" {
  name                = "inspector-weekly-schedule"
  schedule_expression = "cron(0 0 ? * 1 *)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.weekly.name
  target_id = "inspector-lambda"
  arn       = aws_lambda_function.inspector_report.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inspector_report.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly.arn
}
