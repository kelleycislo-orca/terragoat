# Intentionally insecure, for PR scanning tests only. Do not apply.

provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"                      # hardcoded secret (AWS's documented sample key)
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

# Public, unencrypted, unversioned, unlogged S3 bucket
resource "aws_s3_bucket" "pr_test_data" {
  bucket = "pr-test-naughty-bucket"
  acl    = "public-read-write"
  versioning {
    enabled = false
  }
}

resource "aws_s3_bucket_public_access_block" "pr_test_data" {
  bucket                  = aws_s3_bucket.pr_test_data.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

variable "trusted_admin_cidr" {
  description = "IPv4 CIDR block allowed to reach administrative ports (e.g. SSH). Must not be an unrestricted range."
  type        = string
  default     = "<TRUSTED_ADMIN_CIDR>"
}

# Security group open to the world on RDP; SSH restricted to the trusted admin CIDR
resource "aws_security_group" "pr_test_wide_open" {
  name = "pr-test-wide-open"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.trusted_admin_cidr]
  }
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = [var.trusted_admin_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public, unencrypted RDS with no backups and a hardcoded password
resource "aws_db_instance" "pr_test_db" {
  identifier              = "pr-test-db"
  engine                  = "mysql"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  username                = "admin"
  password                = "Password123!"
  publicly_accessible     = true
  storage_encrypted       = false
  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
  vpc_security_group_ids  = [aws_security_group.pr_test_wide_open.id]
}

# Admin-everything IAM policy
resource "aws_iam_policy" "pr_test_admin" {
  name = "pr-test-star-star"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}

# EC2 with public IP, IMDSv1, unencrypted root volume, secrets in user data
resource "aws_instance" "pr_test_vm" {
  ami                         = "ami-0c55b159cbfafe1f0"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.pr_test_wide_open.id]
  user_data                   = "export DB_PASSWORD=Password123!"

  metadata_options {
    http_tokens = "optional"
  }
  root_block_device {
    encrypted = false
  }
}

# Unencrypted EBS volume
resource "aws_ebs_volume" "pr_test_vol" {
  availability_zone = "us-east-1a"
  size              = 10
  encrypted         = true
}
