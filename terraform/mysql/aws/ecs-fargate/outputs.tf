output "ecs_cluster_name" {
  description = "ECS cluster running the Datadog Agent (the existing cluster you supplied, or the newly created one)."
  value       = local.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name (use with aws ecs describe-services)."
  value       = aws_ecs_service.datadog.name
}

output "task_definition_arn" {
  description = "Latest task definition ARN."
  value       = aws_ecs_task_definition.datadog.arn
}

output "log_group_name" {
  description = "CloudWatch log group for the agent container — tail with `aws logs tail <name> --follow`."
  value       = aws_cloudwatch_log_group.datadog.name
}

output "fargate_security_group_id" {
  description = "Security group attached to the Fargate task."
  value       = aws_security_group.fargate_task.id
}

output "db_ingress_rule_id" {
  description = "ID of the security-group ingress rule added to the MySQL database's SG."
  value       = aws_security_group_rule.db_ingress_from_fargate.id
}
