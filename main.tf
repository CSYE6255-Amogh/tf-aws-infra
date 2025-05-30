# main.tf
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = var.vpc_name
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "${var.public_subnet_name}-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "${var.private_subnet_name}-${count.index + 1}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = var.igw_name
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.destination_public_cidr
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.vpc_name}-public"
  }
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.vpc_name}-private"
  }
}

# Associations
resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Updated Security Group for EC2 Instance
resource "aws_security_group" "app_sg" {
  name        = "app_security_group"
  description = "Restrict direct access to app; allow SSH only"
  vpc_id      = aws_vpc.main.id

  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  #   description = "SSH access"
  # }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load Balancer Security Group (lb_sg)
resource "aws_security_group" "lb_sg" {
  name        = "load-balancer-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "load-balancer-sg"
  }
}

# Allow LB to reach app on port 8080
resource "aws_security_group_rule" "app_allow_lb" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lb_sg.id
  security_group_id        = aws_security_group.app_sg.id
  description              = "Allow traffic from Load Balancer"
}

# Allow SSH from anywhere
# resource "aws_security_group_rule" "app_allow_ssh" {
#   type              = "ingress"
#   from_port         = 22
#   to_port           = 22
#   protocol          = "tcp"
#   cidr_blocks       = ["0.0.0.0/0"]
#   security_group_id = aws_security_group.app_sg.id
#   description       = "Allow SSH from anywhere"
# }

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "ec2" {
  description         = "KMS key for EC2 volume encryption"
  enable_key_rotation = true
  is_enabled          = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowRootAccess",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "AllowEC2Service",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowAutoScalingServiceLinkedRoleBasic",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowAutoScalingServiceLinkedRoleCreateGrant",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        },
        Action = [
          "kms:CreateGrant"
        ],
        Resource = "*",
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = true
          }
        }
      }
    ]
  })
}
# Create KMS Key for RDS Encryption
resource "aws_kms_key" "rds" {
  description         = "KMS key for RDS encryption"
  enable_key_rotation = true
  is_enabled          = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowRootAccess",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "AllowRDSServiceToUseKey",
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowRDSServiceCreateGrant",
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = [
          "kms:CreateGrant"
        ],
        Resource = "*",
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = true
          }
        }
      }
    ]
  })
}
resource "aws_kms_key" "s3" {
  description         = "KMS key for S3 encryption"
  enable_key_rotation = true
  is_enabled          = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowRoot",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "AllowS3Service",
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        },
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:DescribeKey"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowEC2RoleToUseS3KMSKey",
        Effect = "Allow",
        Principal = {
          AWS = aws_iam_role.ec2_s3_role.arn
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = "*"
      }
    ]
  })
}
resource "aws_kms_key" "secrets" {
  description         = "KMS key for Secrets Manager"
  enable_key_rotation = true
  is_enabled          = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowRootAccess",
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Sid    = "AllowSecretsManagerServiceAccess",
        Effect = "Allow",
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        },
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:TagResource"
        ],
        Resource = "*"
      },
      {
        Sid    = "AllowEC2InstanceDecrypt",
        Effect = "Allow",
        Principal = {
          AWS = aws_iam_role.ec2_s3_role.arn
        },
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "random_password" "rds" {
  length           = 16
  special          = true
  override_special = "!#$%^&*()-_=+{}[]|:;<>?,.~"
}

resource "aws_secretsmanager_secret" "rds_password_new" {
  name                    = "rds-db-password-new"
  description             = "RDS password stored securely"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0
  depends_on              = [aws_kms_key.secrets] # Ensure KMS key is created before the secret]
}

resource "aws_secretsmanager_secret_version" "rds_password_version" {
  secret_id     = aws_secretsmanager_secret.rds_password_new.id
  secret_string = random_password.rds.result
}

resource "null_resource" "rds_kms_wait" {
  provisioner "local-exec" {
    command = "sleep 30" # Wait for KMS key to be available
  }
  depends_on = [aws_kms_key.rds]
}


# Creating S3 Bucket for Web Application 
resource "random_uuid" "s3_bucket_uuid" {}

resource "aws_s3_bucket" "webapp_s3" {
  bucket        = "${var.s3_bucket_prefix}-${random_uuid.s3_bucket_uuid.result}"
  force_destroy = true # Allows deletion even if the bucket contains objects
  depends_on    = [aws_kms_key.s3]

  tags = {
    Name        = "WebApp S3 Bucket"
    Environment = "Dev"
  }
}

# 🔹 Enable Default Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "webapp_s3_encryption" {
  bucket = aws_s3_bucket.webapp_s3.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

# 🔹 Lifecycle Rule to Transition Objects
resource "aws_s3_bucket_lifecycle_configuration" "webapp_s3_lifecycle" {
  bucket = aws_s3_bucket.webapp_s3.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

#Custom IAM policy for the S3 bucket

resource "aws_iam_policy" "s3_access_policy" {
  name        = "EC2S3AccessPolicy"
  description = "Allows EC2 to access S3 bucket created in Terraform"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.webapp_s3.id}",
          "arn:aws:s3:::${aws_s3_bucket.webapp_s3.id}/*"
        ]
      }
    ]
  })
}

#Creating IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_s3_role" {
  name = "EC2S3AccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Allow EC2 instance to read from Secrets Manager and decrypt KMS keys
resource "aws_iam_policy" "secrets_kms_access_policy" {
  name        = "EC2SecretsKMSAccessPolicy"
  description = "Allows access to secrets and decrypting KMS-protected values"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = aws_secretsmanager_secret.rds_password_new.arn # Replace with specific secret ARN for tighter access
      },
      {
        Effect = "Allow",
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ],
        Resource = aws_kms_key.ec2.arn # Replace with your custom KMS key ARN
      }
    ]
  })
}



# Attach the S3 access policy to the role
resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
  policy_arn = aws_iam_policy.s3_access_policy.arn
  role       = aws_iam_role.ec2_s3_role.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy_attachment" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "secrets_kms_attachment" {
  policy_arn = aws_iam_policy.secrets_kms_access_policy.arn
  role       = aws_iam_role.ec2_s3_role.name
}

# Define IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2InstanceProfile"
  role = aws_iam_role.ec2_s3_role.name
}

resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.main.id # Ensure this matches your VPC

  # Allow inbound traffic from the EC2 instance security group on port 5432
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app_sg.id] # Only allow EC2 access
    description     = "Allow PostgreSQL access from EC2"
  }

  # Allow all outbound traffic (so RDS can respond to EC2 requests)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS-Security-Group"
  }
}

resource "aws_db_subnet_group" "webapp_rds_subnet_group" {
  name        = "webapp-rds-subnet-group"
  description = "Subnet group for RDS instance"
  subnet_ids  = [aws_subnet.private[0].id, aws_subnet.private[1].id] # Use at least two private subnets

  tags = {
    Name = "WebApp-RDS-Subnet-Group"
  }
}

resource "aws_db_parameter_group" "webapp_rds_param_group" {
  name        = "webapp-rds-param-group"
  family      = "postgres17" # Match the PostgreSQL version
  description = "Custom parameter group for WebApp RDS"
}

resource "aws_db_instance" "webapp_rds" {
  identifier          = "csye6225"
  allocated_storage   = 20
  storage_type        = "gp2"
  engine              = "postgres"
  engine_version      = "17"
  instance_class      = "db.t3.micro"
  username            = var.DB_USERNAME
  password            = random_password.rds.result
  db_name             = var.DB_NAME
  storage_encrypted   = true
  kms_key_id          = aws_kms_key.rds.arn
  depends_on          = [aws_kms_key.rds, null_resource.rds_kms_wait]
  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true

  # Use the latest PostgreSQL 17 parameter group
  parameter_group_name = aws_db_parameter_group.webapp_rds_param_group.name

  # Attach the RDS Security Group
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  # Specify the RDS subnet group
  db_subnet_group_name = aws_db_subnet_group.webapp_rds_subnet_group.name


  tags = {
    Name = "WebApp-RDS"
  }
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "webapp_tg" {
  name     = "webapp-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/healthz"
    port                = "8080"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 300
  }
}

# Launch Template 
resource "aws_launch_template" "webapp_template" {
  name          = "csye6225-asg-template"
  image_id      = var.aws_ami_id
  instance_type = var.aws_instance_type
  key_name      = var.aws_key_name
  depends_on    = [aws_kms_key.ec2]
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  # ✅ Attach public IP here
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # Install AWS CLI (if not already present)
              if ! command -v aws &> /dev/null; then
                apt-get update
                sudo snap install aws-cli --classic
              fi

                DB_PASS=$(aws secretsmanager get-secret-value \
                --region us-east-1 \
                --secret-id ${aws_secretsmanager_secret.rds_password_new.name} \
                --query SecretString \
                --output text)

              cat > /opt/csye6225/webapp/.env << EOL
              DATABASE_URL=postgresql://${var.DB_USERNAME}:$DB_PASS@${aws_db_instance.webapp_rds.address}:5432/${var.DB_NAME}
              S3_BUCKET=${aws_s3_bucket.webapp_s3.id}
              EOL
              systemctl daemon-reload
              systemctl restart csye6225.service
              sudo systemctl restart amazon-cloudwatch-agent
              sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                  -a fetch-config \
                  -m ec2 \
                  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                  -s
              EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.aws_volume_size
      volume_type           = var.aws_volume_type
      encrypted             = true
      kms_key_id            = aws_kms_key.ec2.arn
      delete_on_termination = true
    }
  }


  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "webapp-instance"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "webapp_asg" {
  name                      = "csye6225-asg"
  min_size                  = 3
  max_size                  = 5
  desired_capacity          = 3
  vpc_zone_identifier       = aws_subnet.public[*].id
  health_check_type         = "EC2"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.webapp_template.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.webapp_tg.arn]

  tag {
    key                 = "Name"
    value               = "webapp-asg"
    propagate_at_launch = true
  }
}

# Scaling Policy
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale-up-on-cpu"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "high-cpu-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.upscale_threshold
  alarm_description   = "Triggers when average CPU > 35%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up_policy.arn]
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale-down-on-cpu"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.webapp_asg.name
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_alarm" {
  alarm_name          = "low-cpu-usage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = var.downscale_threshold
  alarm_description   = "Triggers when average CPU < 20%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.webapp_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down_policy.arn]
}


# Application Load Balancer
resource "aws_lb" "webapp_alb" {
  name               = "csye6225-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "webapp-alb"
  }
}

# Listener for ALB

# resource "aws_lb_listener" "webapp_listener" {
#   load_balancer_arn = aws_lb.webapp_alb.arn
#   port              = 80
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.webapp_tg.arn
#   }
# }

resource "aws_acm_certificate" "dev_cert" {
  count             = var.subdomain_env == "dev" ? 1 : 0
  domain_name       = "${var.subdomain_env}.amoghjayasimha.me"
  validation_method = "DNS"

  tags = {
    Name = "dev-certificate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "dev_cert_validation" {
  count = var.subdomain_env == "dev" ? 1 : 0

  allow_overwrite = true
  name            = tolist(aws_acm_certificate.dev_cert[0].domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.dev_cert[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  type            = tolist(aws_acm_certificate.dev_cert[0].domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.main_zone.zone_id
}

resource "aws_acm_certificate_validation" "dev_cert_validation" {
  count = var.subdomain_env == "dev" ? 1 : 0

  certificate_arn         = aws_acm_certificate.dev_cert[0].arn
  validation_record_fqdns = [aws_route53_record.dev_cert_validation[0].fqdn]
}




resource "aws_lb_listener" "webapp_https" {
  load_balancer_arn = aws_lb.webapp_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # or "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"

  certificate_arn = var.subdomain_env == "dev" ? aws_acm_certificate_validation.dev_cert_validation[0].certificate_arn : var.demo_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.webapp_tg.arn
  }
}

###############################
# Route53 Hosted Zone Lookup
###############################
data "aws_route53_zone" "main_zone" {
  name         = "${var.subdomain_env}.amoghjayasimha.me"
  private_zone = false
}

# A Record for dev/demo
resource "aws_route53_record" "dev_alias" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = "" # Root domain
  type    = "A"

  alias {
    name                   = aws_lb.webapp_alb.dns_name
    zone_id                = aws_lb.webapp_alb.zone_id
    evaluate_target_health = true
  }
}