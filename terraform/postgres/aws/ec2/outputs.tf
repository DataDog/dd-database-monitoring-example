output "ec2_instance_id" {
  description = "EC2 instance running the Datadog Agent."
  value       = aws_instance.agent.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance (only populated when assign_public_ip = true)."
  value       = aws_instance.agent.public_ip
}

output "ec2_private_ip" {
  description = "Private IP of the EC2 instance."
  value       = aws_instance.agent.private_ip
}

output "ec2_ssh_command" {
  description = "Convenience SSH command (requires assign_public_ip = true and a key_pair_name)."
  value       = var.assign_public_ip && var.key_pair_name != "" ? "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${aws_instance.agent.public_ip}" : "n/a -- set assign_public_ip and key_pair_name to enable, or use SSM: aws ssm start-session --target ${aws_instance.agent.id}"
}

output "agent_host_security_group_id" {
  description = "Security group attached to the EC2 host."
  value       = aws_security_group.agent_host.id
}
