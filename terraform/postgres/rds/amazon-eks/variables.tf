variable "aws_region" {
  description = "AWS region of the EKS cluster and the RDS instance."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for k8s namespace, helm release, and AWS-side resource names. Capped at 20 characters because the datadog/datadog Helm chart appends suffixes up to 43 chars onto the release name (e.g. -datadog-cluster-agent-admission-controller), and Kubernetes service names are capped at 63 chars (DNS-1123)."
  type        = string
  default     = "dbm-postgres-eks"

  validation {
    condition     = length(var.name_prefix) <= 20
    error_message = "name_prefix must be at most 20 characters (the datadog Helm chart's longest service name suffix is 43 chars, leaving 20 for the release name to fit under the 63-char K8s service name limit)."
  }
}

variable "eks_cluster_name" {
  description = "Name of an existing EKS cluster to install the Datadog Agent into. Leave empty (default) to provision a new EKS cluster + managed node group named \"$${name_prefix}-cluster\". When set, eks_node_security_group_id must also be set."
  type        = string
  default     = ""
}

variable "eks_node_security_group_id" {
  description = "Security group attached to the EKS worker nodes when bringing your own cluster (eks_cluster_name set). An ingress rule on the RDS SG is added from this SG so the cluster-check runner pods can reach Postgres. Ignored when provisioning a new cluster (the auto-created cluster security group is used instead)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Inputs used ONLY when provisioning a new EKS cluster
# (eks_cluster_name = "")
# ---------------------------------------------------------------------------

variable "private_subnet_ids" {
  description = "Private subnet IDs (>= 2 in different AZs) for the EKS control plane ENIs and the managed node group. Required when provisioning a new cluster; ignored when bringing your own. Subnets must have NAT egress so the agent + nodes can reach Datadog and pull container images."
  type        = list(string)
  default     = []
}

variable "kubernetes_version" {
  description = "Kubernetes version for the new EKS cluster. Ignored when bringing your own."
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group. Ignored when bringing your own."
  type        = string
  default     = "t3.small"
}

variable "node_desired_count" {
  description = "Desired node count for the managed node group. Ignored when bringing your own."
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum node count for the managed node group. Ignored when bringing your own."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum node count for the managed node group. Ignored when bringing your own."
  type        = number
  default     = 4
}

variable "node_disk_size_gb" {
  description = "Root EBS volume size for managed node group instances (GiB). Ignored when bringing your own."
  type        = number
  default     = 20
}

variable "namespace" {
  description = "Kubernetes namespace for the Datadog Agent helm release. Created if it does not already exist."
  type        = string
  default     = "datadog"
}

variable "rds_security_group_id" {
  description = "Security group attached to the RDS instance. An ingress rule on port 5432 from the EKS node SG is added to it."
  type        = string
}

variable "rds_endpoint" {
  description = "RDS Postgres endpoint hostname (no port suffix)."
  type        = string
}

variable "rds_port" {
  description = "RDS Postgres port."
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
  description = "Password for the datadog Postgres role. Lands in the helm release values (and therefore in a kube ConfigMap) -- see README security note."
  type        = string
  sensitive   = true
}

variable "datadog_api_key" {
  description = "Datadog API key for the destination org."
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key. Required by the Cluster Agent for some features (events, external metrics). Optional for plain DBM."
  type        = string
  sensitive   = true
  default     = ""
}

variable "datadog_site" {
  description = "Datadog site (datadoghq.com, datadoghq.eu, us3.datadoghq.com, etc.)."
  type        = string
  default     = "datadoghq.com"
}

variable "datadog_helm_chart_version" {
  description = "Version of the datadog/datadog Helm chart. Pin for reproducibility."
  type        = string
  default     = "3.74.0"
}

variable "agent_image_tag" {
  description = "Datadog Agent container image tag used by the helm release. The default \"7\" floats to the latest 7.x release; for reproducible deploys pin to a specific tag like \"7.58.2\"."
  type        = string
  default     = "7"
}

variable "cluster_check_runners_replicas" {
  description = "Number of dedicated Cluster Check Runner pods. The Postgres check is dispatched to these pods so it runs once cluster-wide rather than per node."
  type        = number
  default     = 2
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
  description = "Postgres SSL mode used by the agent connection. RDS defaults to require."
  type        = string
  default     = "require"
}
