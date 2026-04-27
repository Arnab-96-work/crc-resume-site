# ---------------- CLOUDFRONT ----------------
output "cloudfront_url" {
  description = "Your live resume URL — paste into your resume and LinkedIn"
  value       = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

output "cloudfront_id" {
  description = "CloudFront Distribution ID — add as GitHub Secret CLOUDFRONT_DISTRIBUTION_ID"
  value       = aws_cloudfront_distribution.cdn.id
}

# ---------------- S3 ----------------
output "s3_bucket_name" {
  description = "S3 bucket name — add as GitHub Secret S3_BUCKET_NAME"
  value       = aws_s3_bucket.resume_bucket.bucket
}

# ---------------- API GATEWAY ----------------
output "api_url" {
  description = "Base API Gateway URL"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}

output "full_api_endpoint" {
  description = "Full visitor counter endpoint — paste into index.html fetch call"
  value       = "${aws_apigatewayv2_api.http_api.api_endpoint}/counter"
}

# ---------------- LAMBDA ----------------
output "lambda_function_name" {
  description = "Lambda function name — add as GitHub Secret LAMBDA_FUNCTION_NAME"
  value       = aws_lambda_function.visitor_counter.function_name
}

# ---------------- DYNAMODB ----------------
output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.visitor_table.name
}
