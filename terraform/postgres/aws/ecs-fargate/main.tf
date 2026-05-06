# Security group for the Fargate task. Egress all (NAT gateway in the chosen
# private subnet is responsible for reaching Datadog and RDS over the VPC).
resource "aws_security_group" "fargate_task" {
  name        = "${var.name_prefix}-task-sg"
  description = "Datadog Agent Fargate task - egress to Datadog and RDS"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}-task-sg" }
}

# Open Postgres ingress on the RDS security group from the Fargate task SG.
# Managed as a standalone rule so the RDS SG itself stays untouched apart from
# this single addition (and is cleanly removed on terraform destroy).
resource "aws_security_group_rule" "rds_ingress_from_fargate" {
  type                     = "ingress"
  description              = "Datadog Agent Fargate task to RDS Postgres"
  from_port                = var.rds_port
  to_port                  = var.rds_port
  protocol                 = "tcp"
  security_group_id        = var.rds_security_group_id
  source_security_group_id = aws_security_group.fargate_task.id
}

resource "aws_cloudwatch_log_group" "datadog" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.name_prefix}-logs" }
}

resource "aws_iam_role" "ecs_execution" {
  name = "${var.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Provision a new ECS cluster only when the caller hasn't supplied an existing
# one. Reusing an existing cluster is the supported path for customers who
# already run other Fargate services in the account.
resource "aws_ecs_cluster" "main" {
  count = var.existing_ecs_cluster_name == "" ? 1 : 0

  name = "${var.name_prefix}-cluster"

  tags = { Name = "${var.name_prefix}-cluster" }
}

locals {
  ecs_cluster_name = var.existing_ecs_cluster_name != "" ? var.existing_ecs_cluster_name : aws_ecs_cluster.main[0].name
}

# Single-container task: the Datadog Agent. The Postgres check is configured
# entirely via Autodiscovery dockerLabels (no file-based config needed).
resource "aws_ecs_task_definition" "datadog" {
  family                   = "${var.name_prefix}-agent"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([
    {
      name      = "datadog-agent"
      image     = var.agent_image
      essential = true
      environment = [
        { name = "DD_API_KEY", value = var.datadog_api_key },
        { name = "DD_SITE", value = var.datadog_site },
        { name = "DD_HOSTNAME", value = "${var.name_prefix}-agent" },
        { name = "ECS_FARGATE", value = "true" },
        { name = "DD_APM_ENABLED", value = "false" },
      ]
      dockerLabels = {
        "com.datadoghq.ad.check_names"  = jsonencode(["postgres"])
        "com.datadoghq.ad.init_configs" = jsonencode([{}])
        "com.datadoghq.ad.instances" = jsonencode([{
          host     = var.rds_endpoint
          port     = var.rds_port
          username = var.datadog_user
          password = var.datadog_user_password
          dbname   = var.database_name
          ssl      = var.ssl_mode
          dbm      = true
          query_metrics = {
            enabled             = true
            collection_interval = 10
          }
          query_samples = {
            enabled             = true
            collection_interval = 1
          }
          collect_schemas = {
            enabled = var.collect_schemas_enabled
          }
          collect_settings = {
            enabled = var.collect_settings_enabled
          }
          tags = var.agent_host_tags
        }])
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.datadog.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "datadog-agent"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "datadog" {
  name            = "${var.name_prefix}-service"
  cluster         = local.ecs_cluster_name
  task_definition = aws_ecs_task_definition.datadog.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.fargate_task.id]
    assign_public_ip = false
  }

  tags = { Name = "${var.name_prefix}-service" }
}
