variable "aws_region" {
  description = "The AWS region to deploy the runners in"
  type        = string
  default     = "us-east-1"
}

variable "gitlab_url" {
  description = "The URL of the GitLab instance"
  type        = string
  default     = "https://gitlab.com/"
}

variable "gitlab_registration_token" {
  description = "The GitLab Runner registration token"
  type        = string
  sensitive   = true
}

# Uncomment if you want to SSH into the instances
# variable "key_name" {
#   description = "SSH key name for EC2 instances"
#   type        = string
# }
