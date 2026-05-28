# DBM on EC2 -- MySQL in AWS

Stands up a single Datadog Agent on an **AWS EC2** instance with **Database Monitoring** enabled, configured to monitor an **existing MySQL database in AWS**.

This is a bring-your-own-DB setup: it does **not** provision the database, a VPC, or the MySQL `datadog` user. It only deploys the agent into the VPC where your MySQL already lives, and opens the right ingress on the database's security group.

Companion to the Postgres EC2 sibling ([`../../postgres/../ec2/`](../../postgres/aws/ec2/)) -- different database, same agent runtime.

## Hosting coverage

This module works for any MySQL database reachable inside an AWS VPC by security group. Point `db_endpoint` and `db_security_group_id` at:

- **Amazon RDS MySQL** -- the RDS endpoint and the RDS security group.
- **Amazon Aurora MySQL** -- the Aurora cluster writer endpoint and the Aurora cluster's security group.
- **Self-hosted MySQL on EC2 in the same VPC** -- the EC2 instance hostname/IP and the security group attached to the MySQL EC2 instance.

For MySQL self-hosted **outside AWS** (on-premises, in another cloud), this AWS-side example does not apply.

## Architecture

```
   ┌────────────────────── existing VPC ──────────────────────┐
   │                                                          │
   │   chosen subnet (public for SSH, or private + SSM)       │
   │   ┌────────────────────────┐    3306    ┌──────────────┐ │
   │   │  EC2 (Amazon Linux 23) │ ─────────▶ │    MySQL     │ │
   │   │  docker run            │            │  (RDS, or    │ │
   │   │  datadog/agent:7       │            │   Aurora, or │ │
   │   │  mysql.d/conf.yaml     │            │   self-      │ │
   │   └─────────┬──────────────┘            │   hosted EC2)│ │
   │             │ outbound                  └──────────────┘ │
   └─────────────┼──────────────────────────────────────────-─┘
                 ▼
            Datadog (DD_SITE)
```

## Prerequisites

- **Terraform >= 1.5** and AWS credentials with permission to create EC2, IAM, and security groups in the target region.
- **An existing MySQL database** (MySQL 5.7+ or 8.0+) -- RDS, Aurora, or self-hosted on EC2.
- **A subnet in the database's VPC** with internet egress (IGW for a public subnet, NAT for a private one) so the agent can reach `*.${DD_SITE}` and pull the agent image.
- **RDS parameter group** (or `my.cnf` for self-hosted) with the following parameters set (Performance Schema is the source of truth for DBM):

  | Parameter | Value | Why |
  |---|---|---|
  | `performance_schema` | `1` | Required for query metrics, samples, and activity |
  | `max_digest_length` | `4096` | Larger captured SQL text |
  | `performance_schema_max_digest_length` | `4096` | Match `max_digest_length` |
  | `performance_schema_max_sql_text_length` | `4096` | Larger captured SQL text |

  Changing `performance_schema` requires an RDS reboot.

- **The MySQL `datadog` user** created on the database -- see *Manual SQL* below.
- A **Datadog API key** for the destination org.
- (Optional) An existing **EC2 key pair** if you want SSH access -- otherwise leave `key_pair_name = ""` and use SSM Session Manager.

## Manual SQL

Run this once against the MySQL instance using the master user.

```sql
-- Create the user
CREATE USER datadog@'%' IDENTIFIED BY '<PASSWORD>';
ALTER USER datadog@'%' WITH MAX_USER_CONNECTIONS 5;

-- Required for monitoring
GRANT REPLICATION CLIENT ON *.* TO datadog@'%';
GRANT PROCESS ON *.* TO datadog@'%';
GRANT SELECT ON performance_schema.* TO datadog@'%';

-- Required for DBM (host metadata + explain plan capture)
GRANT SELECT ON mysql.user TO datadog@'%';

CREATE SCHEMA IF NOT EXISTS datadog;
GRANT EXECUTE ON datadog.* TO datadog@'%';
GRANT CREATE TEMPORARY TABLES ON datadog.* TO datadog@'%';

DELIMITER $$
CREATE PROCEDURE datadog.explain_statement(IN query TEXT)
    SQL SECURITY DEFINER
BEGIN
    SET @explain := CONCAT('EXPLAIN FORMAT=json ', query);
    PREPARE stmt FROM @explain;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END $$
DELIMITER ;

-- Performance Schema consumers (run as master user, not as datadog)
UPDATE performance_schema.setup_consumers SET enabled='YES' WHERE name LIKE 'events_statements_%';
UPDATE performance_schema.setup_consumers SET enabled='YES' WHERE name = 'events_waits_current';
```

Reference: [Setup DBM for MySQL managed by AWS](https://docs.datadoghq.com/database_monitoring/setup_mysql/rds/).

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in vpc_id, subnet_id, db_security_group_id, db_endpoint,
# datadog_user_password, datadog_api_key, and any optional overrides

terraform init
terraform plan
terraform apply
```

`terraform apply` creates ~7 resources: EC2 instance, host security group, database-side ingress rule, IAM role + SSM policy attachment + instance profile.

## Verify

1. Instance is running:
   ```bash
   aws ec2 describe-instances --instance-ids $(terraform output -raw ec2_instance_id) \
     --query 'Reservations[0].Instances[0].{state:State.Name,ip:PublicIpAddress}'
   ```
2. Reach the host (use whichever path matches your config):
   ```bash
   # SSH (assign_public_ip=true and key_pair_name set)
   $(terraform output -raw ec2_ssh_command)

   # SSM (any subnet, no SSH needed)
   aws ssm start-session --target $(terraform output -raw ec2_instance_id)
   ```
3. Check the agent container is healthy:
   ```bash
   docker ps
   docker logs datadog-agent | grep -E '(mysql|dbm)' | tail -50
   ```
   You should see `Running check mysql` and no `performance_schema` errors.
4. In the Datadog UI:
   - **Infrastructure --> Hosts**: the EC2 host appears.
   - **Databases --> List**: the MySQL host appears with DBM enabled.
   - **Databases --> Query Metrics**: rows render within ~2 minutes of database traffic.

## Teardown

```bash
terraform destroy
```

Removes the EC2 instance, host SG, IAM role, and the ingress rule added to the database SG. The MySQL instance, VPC, and the `datadog` user are untouched.

## Security note

The `datadog_user_password` is rendered into `/etc/datadog-agent/conf.d/mysql.d/conf.yaml` on the host via `user_data` (cloud-init). EC2 user_data is readable by anyone with `ec2:DescribeInstanceAttribute` on the instance, and the rendered file is readable by anyone with shell access. This is fine for a demo; for production, switch to **AWS Secrets Manager** + a small fetch script in `user_data`, or move to ECS Fargate with `secrets[]`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent logs show `connection refused` to database | Database SG ingress rule didn't apply, or instance is in a subnet with no route to the database |
| Agent logs show `performance_schema is disabled` | Parameter group missing `performance_schema=1`, or RDS not rebooted after the change |
| Agent logs show `Access denied for user 'datadog'` | Manual SQL not run, or grants missing |
| `query_metrics` empty but check is running | `events_statements_*` consumers not enabled in `performance_schema.setup_consumers` |
| `query_samples` empty | `datadog.explain_statement` procedure not created, or `EXECUTE` not granted on `datadog.*` |
| No data in Datadog UI | API key wrong, `DD_SITE` mismatched, or instance can't reach `*.${DD_SITE}` (no IGW/NAT egress) |
| `docker: command not found` on first SSH | `user_data` still running -- wait ~60s and re-check with `cloud-init status --wait` |

## Files

- `versions.tf` -- Terraform + provider pins
- `variables.tf` -- inputs (secrets marked `sensitive`)
- `main.tf` -- EC2 instance, IAM role, security group, database ingress rule
- `user_data.sh.tpl` -- cloud-init script: installs Docker, drops conf.yaml, runs the agent
- `outputs.tf` -- useful identifiers for verification
- `terraform.tfvars.example` -- fill-in-the-blanks template
