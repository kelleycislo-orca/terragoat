

Pr test2 · TF
# =====================================================================
# INTENTIONALLY INSECURE - FOR ORCA PR SCAN TESTING ONLY. DO NOT APPLY.
# Every resource below is deliberately misconfigured.
# All "secrets" are AWS documentation example values / dummy strings.
# =====================================================================
 
provider "aws" {
  region = "us-east-1"
}
 
# ---------------------------------------------------------------------
# IAM - full admin wildcard policy, attached to a user, inline creds
# ---------------------------------------------------------------------
resource "aws_iam_user" "pr2_admin_user" {
  name = "pr2-admin-user"
}
 
resource "aws_iam_access_key" "pr2_admin_key" {
  user = aws_iam_user.pr2_admin_user.name
}
 
resource "aws_iam_user_policy" "pr2_star_star" {
  name = "pr2-star-star"
  user = aws_iam_user.pr2_admin_user.name
 
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*"
      Resource = "*"
    }]
  })
}
 
resource "aws_iam_role" "pr2_any_principal" {
  name = "pr2-any-principal-role"
 
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "sts:AssumeRole"
    }]
  })
}
 
resource "aws_iam_role_policy_attachment" "pr2_admin_attach" {
  role       = aws_iam_role.pr2_any_principal.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
 
resource "aws_iam_account_password_policy" "pr2_weak" {
  minimum_password_length        = 6
  require_lowercase_characters   = false
  require_uppercase_characters   = false
  require_numbers                = false
  require_symbols                = false
  allow_users_to_change_password = true
  password_reuse_prevention      = 0
}
 
# ---------------------------------------------------------------------
# Network - all ports open to the world
# ---------------------------------------------------------------------
resource "aws_security_group" "pr2_all_open" {
  name        = "pr2-all-open"
  description = "everything open"
 
  ingress {
    from_port        = 0
    to_port          = 65535
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
 
resource "aws_network_acl_rule" "pr2_nacl_all" {
  network_acl_id = "acl-00000000000000000"
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}
 
# ---------------------------------------------------------------------
# RDS - public, unencrypted, no backups, hardcoded password
# ---------------------------------------------------------------------
resource "aws_db_instance" "pr2_public_db" {
  identifier                          = "pr2-public-db"
  engine                              = "mysql"
  engine_version                      = "5.7"
  instance_class                      = "db.t3.micro"
  allocated_storage                   = 20
  username                            = "admin"
  password                            = "Password123!"
  publicly_accessible                 = true
  storage_encrypted                   = false
  backup_retention_period             = 0
  deletion_protection                 = false
  skip_final_snapshot                 = true
  multi_az                            = false
  iam_database_authentication_enabled = false
  auto_minor_version_upgrade          = false
  monitoring_interval                 = 0
  vpc_security_group_ids              = [aws_security_group.pr2_all_open.id]
}
 
resource "aws_db_snapshot" "pr2_snap" {
  db_instance_identifier = aws_db_instance.pr2_public_db.identifier
  db_snapshot_identifier = "pr2-snap"
}
 
# ---------------------------------------------------------------------
# S3 - public bucket policy, no encryption, no versioning, no logging
# ---------------------------------------------------------------------
resource "aws_s3_bucket" "pr2_public_bucket" {
  bucket        = "pr2-wide-open-bucket"
  force_destroy = true
}
 
resource "aws_s3_bucket_public_access_block" "pr2_pab" {
  bucket                  = aws_s3_bucket.pr2_public_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
 
resource "aws_s3_bucket_policy" "pr2_public_policy" {
  bucket = aws_s3_bucket.pr2_public_bucket.id
 
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.pr2_public_bucket.arn,
        "${aws_s3_bucket.pr2_public_bucket.arn}/*"
      ]
    }]
  })
}
 
# ---------------------------------------------------------------------
# EC2 - IMDSv1, public IP, unencrypted root, secrets in user data
# ---------------------------------------------------------------------
resource "aws_instance" "pr2_bastion" {
  ami                         = "ami-0c55b159cbfafe1f0"
  instance_type               = "t3.micro"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.pr2_all_open.id]
  monitoring                  = false
  ebs_optimized               = false
 
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional"
  }
 
  root_block_device {
    encrypted   = false
    volume_size = 8
  }
 
  user_data = <<-EOF
    #!/bin/bash
    export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
    export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
    export DB_PASSWORD=Password123!
  EOF
}
 
resource "aws_ebs_snapshot" "pr2_snap" {
  volume_id = "vol-00000000000000000"
}
 
resource "aws_ebs_encryption_by_default" "pr2_off" {
  enabled = false
}
 
# ---------------------------------------------------------------------
# EKS - public endpoint open to 0.0.0.0/0, no logging, no secrets encryption
# ---------------------------------------------------------------------
resource "aws_eks_cluster" "pr2_eks" {
  name     = "pr2-eks"
  role_arn = aws_iam_role.pr2_any_principal.arn
  version  = "1.21"
 
  vpc_config {
    subnet_ids              = ["subnet-00000000000000000", "subnet-11111111111111111"]
    endpoint_public_access  = true
    endpoint_private_access = false
    public_access_cidrs     = ["0.0.0.0/0"]
  }
 
  enabled_cluster_log_types = []
}
 
# ---------------------------------------------------------------------
# Lambda - plaintext secrets in env vars, public invoke permission
# ---------------------------------------------------------------------
resource "aws_lambda_function" "pr2_fn" {
  function_name = "pr2-fn"
  role          = aws_iam_role.pr2_any_principal.arn
  handler       = "index.handler"
  runtime       = "python3.7"
  filename      = "lambda.zip"
 
  environment {
    variables = {
      AWS_ACCESS_KEY_ID     = "AKIAIOSFODNN7EXAMPLE"
      AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      DB_PASSWORD           = "Password123!"
    }
  }
}
 
resource "aws_lambda_permission" "pr2_public_invoke" {
  statement_id  = "AllowPublicInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pr2_fn.function_name
  principal     = "*"
}
 
resource "aws_lambda_function_url" "pr2_fn_url" {
  function_name      = aws_lambda_function.pr2_fn.function_name
  authorization_type = "NONE"
}
 
# ---------------------------------------------------------------------
# Logging / detection disabled
# ---------------------------------------------------------------------
resource "aws_cloudtrail" "pr2_trail" {
  name                          = "pr2-trail"
  s3_bucket_name                = aws_s3_bucket.pr2_public_bucket.id
  enable_logging                = false
  is_multi_region_trail         = false
  include_global_service_events = false
  enable_log_file_validation    = false
}
 
resource "aws_guardduty_detector" "pr2_gd" {
  enable = false
}
 
resource "aws_kms_key" "pr2_key" {
  description             = "pr2 key"
  enable_key_rotation     = false
  deletion_window_in_days = 7
 
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}
 
# ---------------------------------------------------------------------
# Data services - public / unencrypted
# ---------------------------------------------------------------------
resource "aws_redshift_cluster" "pr2_redshift" {
  cluster_identifier  = "pr2-redshift"
  node_type           = "dc2.large"
  master_username     = "admin"
  master_password     = "Password123!"
  publicly_accessible = true
  encrypted           = false
  skip_final_snapshot = true
}
 
resource "aws_elasticsearch_domain" "pr2_es" {
  domain_name           = "pr2-es"
  elasticsearch_version = "6.8"
 
  encrypt_at_rest {
    enabled = false
  }
 
  node_to_node_encryption {
    enabled = false
  }
 
  domain_endpoint_options {
    enforce_https = false
  }
 
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "es:*"
      Resource  = "*"
    }]
  })
}
 
resource "aws_efs_file_system" "pr2_efs" {
  creation_token = "pr2-efs"
  encrypted      = false
}
 
resource "aws_dynamodb_table" "pr2_table" {
  name         = "pr2-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
 
  attribute {
    name = "id"
    type = "S"
  }
 
  point_in_time_recovery {
    enabled = false
  }
}
 
resource "aws_sqs_queue" "pr2_queue" {
  name                    = "pr2-queue"
  sqs_managed_sse_enabled = false
}
 
resource "aws_sqs_queue_policy" "pr2_queue_policy" {
  queue_url = aws_sqs_queue.pr2_queue.id
 
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = aws_sqs_queue.pr2_queue.arn
    }]
  })
}
 
resource "aws_sns_topic" "pr2_topic" {
  name = "pr2-topic"
}
 
resource "aws_ecr_repository" "pr2_ecr" {
  name                 = "pr2-ecr"
  image_tag_mutability = "MUTABLE"
 
  image_scanning_configuration {
    scan_on_push = false
  }
}
 
# ---------------------------------------------------------------------
# Load balancer - plain HTTP listener, no TLS
# ---------------------------------------------------------------------
resource "aws_lb" "pr2_alb" {
  name                       = "pr2-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.pr2_all_open.id]
  subnets                    = ["subnet-00000000000000000", "subnet-11111111111111111"]
  drop_invalid_header_fields = false
  enable_deletion_protection = false
}
 
resource "aws_lb_listener" "pr2_http" {
  load_balancer_arn = aws_lb.pr2_alb.arn
  port              = 80
  protocol          = "HTTP"
 
  default_action {
    type             = "forward"
    target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/pr2/0000000000000000"
  }
}
 
Claude finished the response
