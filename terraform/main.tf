# ---------------- S3 BUCKET ----------------
resource "aws_s3_bucket" "resume_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.resume_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- CLOUDFRONT OAC ----------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "crc-oac"
  description                       = "OAC for S3 resume bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------- CLOUDFRONT DISTRIBUTION ----------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = "CRC CloudFront Distribution-v2"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"

  origin {
    domain_name              = aws_s3_bucket.resume_bucket.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# ---------------- S3 BUCKET POLICY (ALLOW CLOUDFRONT ONLY) ----------------
resource "aws_s3_bucket_policy" "policy" {
  bucket     = aws_s3_bucket.resume_bucket.id
  depends_on = [aws_s3_bucket_public_access_block.block]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.resume_bucket.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
        }
      }
    }]
  })
}

# ---------------- DYNAMODB ----------------
resource "aws_dynamodb_table" "visitor_table" {
  name         = "crc-visitor-counter-v2"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "initial_item" {
  table_name = aws_dynamodb_table.visitor_table.name
  hash_key   = aws_dynamodb_table.visitor_table.hash_key

  item = jsonencode({
    id    = { S = "visitor-counter" }
    views = { N = "1" }
  })

  lifecycle {
    ignore_changes = [item]
  }
}

# ---------------- IAM ROLE FOR LAMBDA ----------------
resource "aws_iam_role" "lambda_role" {
  name = "crc-lambda-role-v2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "crc-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.visitor_table.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------- LAMBDA ----------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/lambda/lambda_function.py"
  output_path = "${path.module}/../backend/lambda/lambda.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.visitor_table.name
    }
  }

  depends_on = [aws_iam_role_policy.lambda_policy]
}

# ---------------- CLOUDWATCH ALARM ----------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "crc-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when Lambda has any errors"

  dimensions = {
    FunctionName = aws_lambda_function.visitor_counter.function_name
  }
}

# ---------------- API GATEWAY ----------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "crc-api-v2"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.visitor_counter.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "counter_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /counter"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
