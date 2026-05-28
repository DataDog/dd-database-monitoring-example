# Latest Amazon Linux 2023 AMI in the target region.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Pre-render the MySQL integration config as YAML so the user_data heredoc
# just emits a literal value. yamlencode handles all escaping, so passwords or
# tag values containing ":", "#", quotes, or newlines round-trip safely.
locals {
  mysql_check_yaml = yamlencode({
    init_config = {}
    instances = [{
      dbm      = true
      host     = var.db_endpoint
      port     = var.db_port
      username = var.datadog_user
      password = var.datadog_user_password
      options = {
        replication          = var.replication_enabled
        extra_status_metrics = true
        extra_innodb_metrics = true
        schemas_collection = {
          enabled = var.schemas_collection_enabled
        }
      }
      query_metrics = {
        enabled             = true
        collection_interval = 10
      }
      query_samples = {
        enabled             = true
        collection_interval = 1
      }
      query_activity = {
        enabled             = true
        collection_interval = 10
      }
      tags = var.agent_host_tags
    }]
  })
}

# Security group for the EC2 instance. SSH ingress is opt-in (only added if
# ssh_ingress_cidrs is non-empty); egress is wide open so the agent can pull
# the image, reach Datadog, and reach the database.
resource "aws_security_group" "agent_host" {
  name        = "${var.name_prefix}-host-sg"
  description = "Datadog Agent EC2 host - SSH inbound from allowed IPs, all outbound"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ssh_ingress_cidrs
    content {
      description = "SSH from ${ingress.value}"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-host-sg" }
}

# Open MySQL ingress on the database's security group from the EC2 host SG.
# Managed as a standalone rule so the database's SG itself stays untouched apart
# from this single addition (and is cleanly removed on terraform destroy).
resource "aws_security_group_rule" "db_ingress_from_agent" {
  type                     = "ingress"
  description              = "Datadog Agent EC2 host to MySQL"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = aws_security_group.agent_host.id
}

# Instance profile -- only used so SSM Session Manager works out of the box
# (handy when assign_public_ip = false and there is no SSH path).
resource "aws_iam_role" "ec2" {
  name = "${var.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# Single EC2 host running the Datadog Agent in Docker. The MySQL check is
# configured via a conf.yaml dropped into /etc/datadog-agent/conf.d/mysql.d
# and bind-mounted into the container.
resource "aws_instance" "agent" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.agent_host.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = var.assign_public_ip
  key_name                    = var.key_pair_name != "" ? var.key_pair_name : null

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    mysql_check_yaml = local.mysql_check_yaml
    datadog_api_key  = var.datadog_api_key
    datadog_site     = var.datadog_site
    agent_image      = var.agent_image
  })

  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
    # Bridge-networked Docker (the default for `docker run` without --network host)
    # adds one network hop, which drops the IMDSv2 token's TTL to 0 by the time
    # the response reaches the container. Setting hop_limit=2 keeps IMDS reachable
    # so the Agent can pick up EC2 metadata + AWS host tags.
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = { Name = "${var.name_prefix}-agent" }
}
