variable "aws_region" {
  description = "AWS region where the EC2 instance runs. Should match the database's region."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "dbm-postgres-ec2"
}

variable "vpc_id" {
  description = "VPC where the Postgres database lives. The EC2 instance is launched in this same VPC."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the EC2 instance. Must route to the database and to the internet (for pulling the agent image and reaching Datadog)."
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP to the EC2 instance. Set true for a public-subnet demo (SSH from ssh_ingress_cidrs); set false for a private subnet (use SSM Session Manager)."
  type        = bool
  default     = true
}

variable "db_security_group_id" {
  description = "Security group attached to your Postgres database (RDS instance SG, Aurora cluster SG, or EC2 instance SG for self-hosted). An ingress rule on the Postgres port from the agent EC2 instance SG is added to it."
  type        = string
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
  description = "Postgres role the Agent connects as. Must already exist (created out-of-band -- see README)."
  type        = string
  default     = "datadog"
}

variable "datadog_user_password" {
  description = "Password for the datadog Postgres role. Lands in the conf.yaml on the EC2 instance -- see README security note."
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

variable "instance_type" {
  description = "EC2 instance type for the Datadog Agent host."
  type        = string
  default     = "t3.small"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access. Leave empty to skip SSH (use SSM Session Manager via the instance profile)."
  type        = string
  default     = ""
}

variable "ssh_ingress_cidrs" {
  description = "CIDR blocks allowed to SSH into the EC2 instance. Empty list disables SSH ingress (use SSM)."
  type        = list(string)
  default     = []
}

variable "root_volume_size_gb" {
  description = "EC2 root volume size in GiB."
  type        = number
  default     = 20
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
  description = "Tags applied to the Postgres instance via the check config (env, team, etc.)."
  type        = list(string)
  default     = ["env:demo", "team:dbm"]
}

variable "ssl_mode" {
  description = "Postgres SSL mode used by the agent connection. RDS and Aurora default to `require`; for self-hosted, set to whatever your `postgresql.conf` enforces."
  type        = string
  default     = "require"
}
