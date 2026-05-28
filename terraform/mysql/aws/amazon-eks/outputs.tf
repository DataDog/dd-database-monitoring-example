output "eks_cluster_name" {
  description = "EKS cluster name. The newly-created one in greenfield mode, or the existing BYO cluster name."
  value       = local.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint. Use with kubectl: aws eks update-kubeconfig --name $(terraform output -raw eks_cluster_name) --region <region>."
  value       = data.aws_eks_cluster.this.endpoint
}

output "eks_node_security_group_id" {
  description = "Security group ID attached to EKS worker nodes. Resolved from greenfield (auto-created cluster SG) or BYO (customer-supplied)."
  value       = local.node_security_group_id
}

output "namespace" {
  description = "Kubernetes namespace where the Datadog Agent helm release is installed."
  value       = kubernetes_namespace.datadog.metadata[0].name
}

output "helm_release_name" {
  description = "Helm release name (use with `helm status -n <namespace>`)."
  value       = helm_release.datadog.name
}

output "cluster_check_runner_deployment" {
  description = "Deployment name of the Cluster Check Runner pods that execute the MySQL check."
  value       = "${helm_release.datadog.name}-datadog-clusterchecks"
}

output "cluster_agent_deployment" {
  description = "Deployment name of the Datadog Cluster Agent."
  value       = "${helm_release.datadog.name}-datadog-cluster-agent"
}

output "db_ingress_rule_id" {
  description = "ID of the security-group ingress rule added to the MySQL database's SG."
  value       = aws_security_group_rule.db_ingress_from_eks_nodes.id
}
