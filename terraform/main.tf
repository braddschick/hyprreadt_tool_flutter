terraform {
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

# -----------------------------------------------------------------------------
# VPC and Security Group
# -----------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "runner_sg" {
  name        = "gitlab-runner-sg"
  description = "Security group for GitLab Runners"
  vpc_id      = data.aws_vpc.default.id

  # Allow egress to internet (required for registering runners, downloading flutter, etc.)
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# -----------------------------------------------------------------------------
# Windows Runner (EC2 Instance)
# -----------------------------------------------------------------------------
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
}

resource "aws_instance" "windows_runner" {
  ami           = data.aws_ami.windows.id
  instance_type = "t3.medium" # Windows instances need at least 2 vCPUs/4GB RAM for building
  # key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.runner_sg.id]

  # User Data script dynamically passes the GitLab token to the Windows bootstrap
  user_data = templatefile("${path.module}/scripts/windows_bootstrap.ps1", {
    gitlab_url   = var.gitlab_url
    runner_token = var.gitlab_registration_token
  })

  tags = {
    Name = "hyprready-windows-builder"
  }
}

# -----------------------------------------------------------------------------
# macOS ARM Runner (Mac Dedicated Host + EC2 Instance)
# macOS EC2 instances MUST run on Dedicated Hosts.
# -----------------------------------------------------------------------------
data "aws_ami" "macos_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-mac-14.*-arm64"] # macOS Sonoma ARM64
  }
}

# You must allocate a Dedicated Host for Mac instances in AWS
resource "aws_ec2_host" "mac_host" {
  instance_type     = "mac2.metal" # Requires M1 Mac metal instance
  availability_zone = "${var.aws_region}a"
  auto_placement    = "on"
}

resource "aws_instance" "macos_runner" {
  ami           = data.aws_ami.macos_arm.id
  instance_type = "mac2.metal" # M1 instances

  host_id = aws_ec2_host.mac_host.id
  # key_name = var.key_name

  vpc_security_group_ids = [aws_security_group.runner_sg.id]

  # User Data script for Mac dynamically passes the GitLab token
  user_data = templatefile("${path.module}/scripts/macos_bootstrap.sh", {
    gitlab_url   = var.gitlab_url
    runner_token = var.gitlab_registration_token
  })

  tags = {
    Name = "hyprready-macos-arm-builder"
  }
}
