#!/bin/bash
set -euo pipefail

# Install Docker (Amazon Linux 2023).
dnf install -y docker
systemctl enable docker
systemctl start docker

# Allow ec2-user to run docker without sudo (matches the unprivileged
# `docker ps` / `docker logs datadog-agent` commands shown in the README).
# Takes effect on the next login session.
usermod -aG docker ec2-user

# Drop the Postgres integration config where the agent container will mount it.
# postgres_check_yaml is rendered by Terraform via yamlencode so any special
# characters in the password, tags, or other inputs are properly escaped.
mkdir -p /etc/datadog-agent/conf.d/postgres.d
cat > /etc/datadog-agent/conf.d/postgres.d/conf.yaml <<'YAML'
${postgres_check_yaml}
YAML

# Run the agent container, mounting only the postgres.d directory so the
# integration picks up our config.
docker run -d \
  --name datadog-agent \
  --restart unless-stopped \
  -e DD_API_KEY=${datadog_api_key} \
  -e DD_SITE=${datadog_site} \
  -e DD_HOSTNAME=$(hostname -s) \
  -v /etc/datadog-agent/conf.d/postgres.d:/etc/datadog-agent/conf.d/postgres.d:ro \
  ${agent_image}
