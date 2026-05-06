variable "aws_region" {
  description = "AWS region where the ECS cluster runs. Should match the database's region."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "dbm-postgres-fargate"
}

variable "vpc_id" {
  description = "VPC where the Postgres database lives. The Fargate task is launched in this same VPC."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the Fargate task. Must already have NAT egress so the agent can reach Datadog."
  type        = list(string)
}

variable "db_security_group_id" {
  description = "Security group attached to your Postgres database (RDS instance SG, Aurora cluster SG, or EC2 instance SG for self-hosted). An ingress rule on port 5432 from the Fargate task SG is added to it."
  type        = string
}

variable "existing_ecs_cluster_name" {
  description = "Name of an existing ECS cluster to attach the agent service to. Leave empty (default) to provision a new cluster named \"$${name_prefix}-cluster\"."
  type        = string
  default     = ""
}

variable "db_endpoint" {
  description = "Postgres endpoint hostname (no port). For RDS, the RDS endpoint; for Aurora, the cluster writer endpoint; for self-hosted on EC2, the instance hostname or IP."
  type        = string
}

variable "db_port" {
  description = "Postgres TCP port."
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Postgres database name the agent connects to."
  type        = string
}

variable "datadog_user" {
  description = "Postgres role the Agent connects as. Must already exist (created out-of-band — see README)."
  type        = string
  default     = "datadog"
}

variable "datadog_user_password" {
  description = "Password for the datadog Postgres role. Lands in the ECS task definition — see README security note."
  type        = string
  sensitive   = true
}

variable "datadog_api_key" {
  description = "Datadog API key for the destination org."
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Datadog site (datadoghq.com, datadoghq.eu, us3.datadoghq.com, etc.)."
  type        = string
  default     = "datadoghq.com"
}

variable "agent_image" {
  description = "Datadog Agent container image. Pin to a digest or specific tag for reproducibility."
  type        = string
  default     = "public.ecr.aws/datadog/agent:7"
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate task memory (MiB)."
  type        = string
  default     = "1024"
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the agent container logs."
  type        = number
  default     = 14
}

variable "collect_schemas_enabled" {
  description = "Enable Postgres schema collection (table/column/index metadata)."
  type        = bool
  default     = true
}

variable "collect_settings_enabled" {
  description = "Enable Postgres settings collection (pg_settings)."
  type        = bool
  default     = true
}

variable "agent_host_tags" {
  description = "Tags applied to the Postgres instance via the AD config (env, team, etc.)."
  type        = list(string)
  default     = ["env:demo", "team:dbm"]
}

variable "ssl_mode" {
  description = "Postgres SSL mode used by the agent connection. RDS and Aurora default to `require`; for self-hosted, set to whatever your `postgresql.conf` enforces."
  type        = string
  default     = "require"
}
