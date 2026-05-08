locals {
  # Greenfield mode when no existing cluster name is supplied.
  manage_cluster = var.eks_cluster_name == ""

  # Resolved cluster name — either the BYO name or the freshly-created one.
  cluster_name = local.manage_cluster ? aws_eks_cluster.main[0].name : var.eks_cluster_name

  # Source SG for the database's ingress rule. In greenfield mode we use the
  # cluster's auto-created cluster security group, which the managed node group
  # attaches to every node by default. In BYO mode the customer supplies it.
  node_security_group_id = local.manage_cluster ? aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id : var.eks_node_security_group_id
}

# ---------------------------------------------------------------------------
# Greenfield path: provision a new EKS cluster + managed node group.
# Skipped entirely when eks_cluster_name is set (BYO).
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  count = local.manage_cluster ? 1 : 0
  name  = "${var.name_prefix}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_amazoneks" {
  count      = local.manage_cluster ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  count      = local.manage_cluster ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_eks_cluster" "main" {
  count    = local.manage_cluster ? 1 : 0
  name     = "${var.name_prefix}-cluster"
  role_arn = aws_iam_role.cluster[0].arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_amazoneks,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
  ]

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_ids) >= 2
      error_message = "private_subnet_ids must contain at least 2 subnets (in different AZs) when provisioning a new EKS cluster (eks_cluster_name empty)."
    }
  }
}

resource "aws_iam_role" "node" {
  count = local.manage_cluster ? 1 : 0
  name  = "${var.name_prefix}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count      = local.manage_cluster ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count      = local.manage_cluster ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count      = local.manage_cluster ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_node_group" "main" {
  count           = local.manage_cluster ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.node_instance_type]
  disk_size       = var.node_disk_size_gb

  scaling_config {
    desired_size = var.node_desired_count
    min_size     = var.node_min_count
    max_size     = var.node_max_count
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# ---------------------------------------------------------------------------
# Always-on path: agent install + database SG ingress rule. Identical for both
# BYO and greenfield modes; just sources its inputs from the locals above.
# ---------------------------------------------------------------------------

# Open Postgres ingress on the database's security group from the EKS node SG.
# Managed as a standalone rule so the database's SG itself stays untouched apart
# from this single addition (and is cleanly removed on terraform destroy).
resource "aws_security_group_rule" "db_ingress_from_eks_nodes" {
  type                     = "ingress"
  description              = "Datadog Agent (EKS) cluster-check runners to Postgres"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = var.db_security_group_id
  source_security_group_id = local.node_security_group_id

  lifecycle {
    precondition {
      condition     = (var.eks_cluster_name == "") == (var.eks_node_security_group_id == "")
      error_message = "eks_cluster_name and eks_node_security_group_id must both be set (BYO mode) or both empty (greenfield mode)."
    }
  }
}

resource "kubernetes_namespace" "datadog" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "datadog-agent"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Helm release: deploys the node Agent DaemonSet, the Cluster Agent, and the
# Cluster Check Runner Deployment. The Postgres check runs as a cluster check
# (single-instance, dispatched by the Cluster Agent to a CLC runner pod) -- the
# right pattern for monitoring an external resource like a managed Postgres,
# so that DBM data isn't duplicated by every node in the cluster.
resource "helm_release" "datadog" {
  # Keep the release name short — the datadog/datadog chart appends suffixes
  # up to 43 chars (e.g. -datadog-cluster-agent-admission-controller) onto the
  # release name to derive Kubernetes service names. K8s service names are
  # capped at 63 chars (DNS-1123), so the release name must be <= 20 chars.
  name       = var.name_prefix
  namespace  = kubernetes_namespace.datadog.metadata[0].name
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  version    = var.datadog_helm_chart_version

  values = [
    yamlencode({
      datadog = {
        apiKey      = var.datadog_api_key
        appKey      = var.datadog_app_key
        site        = var.datadog_site
        clusterName = local.cluster_name
        tags        = var.agent_host_tags

        clusterChecks = {
          enabled = true
        }
      }

      agents = {
        image = {
          tag = var.agent_image_tag
        }
      }

      # Cluster Agent. Image tag is intentionally omitted so the helm chart's
      # pinned cluster-agent version takes effect — Datadog publishes the
      # cluster-agent only with specific version tags (7.55.0, 7.56.0, ...),
      # NOT with a "7" major-version shortcut like the main agent has.
      #
      # The Postgres check is placed in `clusterAgent.confd` (NOT `datadog.confd`)
      # so the Cluster Agent reads it directly and dispatches it to a CLC runner.
      # Putting it under `datadog.confd` would route it through node-agent
      # autodiscovery, which the chart does not propagate to the cluster agent
      # for cluster-check dispatch — the check would be configured on the
      # DaemonSet pods but never actually scheduled.
      clusterAgent = {
        enabled  = true
        replicas = 2
        confd = {
          "postgres.yaml" = yamlencode({
            cluster_check = true
            init_config   = {}
            instances = [
              {
                dbm      = true
                host     = var.db_endpoint
                port     = var.db_port
                username = var.datadog_user
                password = var.datadog_user_password
                dbname   = var.database_name
                ssl      = var.ssl_mode
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
              }
            ]
          })
        }
      }

      # Dedicated Cluster Check Runner Deployment. The Postgres cluster check
      # runs in these pods rather than on a node Agent, so database connectivity
      # is only required from this set of pods.
      clusterChecksRunner = {
        enabled  = true
        replicas = var.cluster_check_runners_replicas
      }
    })
  ]

  # In greenfield mode, the helm release must wait for the node group to be
  # ready (otherwise pods stay Pending). In BYO mode the node group already
  # exists; the [0] indexing into a length-0 list is fine because aws_eks_node_group
  # has count=0 and Terraform handles that gracefully.
  depends_on = [
    aws_security_group_rule.db_ingress_from_eks_nodes,
    aws_eks_node_group.main,
  ]
}
