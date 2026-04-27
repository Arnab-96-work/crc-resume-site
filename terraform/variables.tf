variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "ap-south-1"
}

variable "bucket_name" {
  description = "S3 bucket name — must be globally unique across all AWS accounts"
  type        = string
  default     = "arnab-mallick-resume"
}

variable "lambda_function_name" {
  description = "Lambda function name"
  type        = string
  default     = "crc-visitor-counter-v2"
}
