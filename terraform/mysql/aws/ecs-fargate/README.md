# DBM on ECS Fargate — MySQL in AWS

Stands up a single Datadog Agent on **AWS ECS Fargate** with **Database Monitoring** enabled, configured to monitor an **existing MySQL database in AWS** via Autodiscovery.

This is a bring-your-own-DB setup: it does **not** provision the database, a VPC, or the MySQL `datadog` user. It only deploys the agent into the VPC where your MySQL already lives, and opens the right ingress on the database's security group.

Companion to the Postgres ECS Fargate sibling ([`../../postgres/aws/ecs-fargate/`](../../postgres/aws/ecs-fargate/)) — different database, same agent runtime.

## Hosting coverage

This module works for any MySQL database reachable inside an AWS VPC by security group. Point `db_endpoint` and `db_security_group_id` at:

- **Amazon RDS MySQL** — the RDS endpoint and the RDS security group.
- **Amazon Aurora MySQL** — the Aurora cluster writer endpoint and the Aurora cluster's security group.
- **Self-hosted MySQL on EC2 in the same VPC** — the EC2 instance hostname/IP and the security group attached to the MySQL EC2 instance.

For MySQL self-hosted **outside AWS** (on-premises, in another cloud), this AWS-side example does not apply.

## Architecture

```
   ┌────────────────────────── existing VPC ──────────────────────────┐
   │                                                                  │
   │   private subnet (with NAT egress)            ┌──────────────┐   │
   │   ┌────────────────────────┐    3306          │    MySQL     │   │
   │   │  Fargate task          │ ───────────────▶ │  (RDS, or    │   │
   │   │  datadog/agent:7       │                  │   Aurora, or │   │
   │   │  ECS_FARGATE=true      │                  │   self-      │   │
   │   │  AD: mysql + dbm       │                  │   hosted EC2)│   │
   │   └─────────┬──────────────┘                  └──────────────┘   │
   │             │ NAT egress                                         │
   └─────────────┼────────────────────────────────────────────────────┘
                 ▼
            Datadog (DD_SITE)
```

## Prerequisites

- **Terraform >= 1.5** and AWS credentials with permission to create ECS, IAM, security groups, and CloudWatch log groups in the target region.
- **An existing MySQL database** (MySQL 5.7+ or 8.0+) — RDS, Aurora, or self-hosted on EC2.
- **A private subnet in the database's VPC** that already has NAT egress to the internet (the agent must reach `*.${DD_SITE}`).
- **RDS parameter group** (or `my.cnf` for self-hosted) with the following parameters set (Performance Schema is the source of truth for DBM):

  | Parameter | Value | Why |
  |---|---|---|
  | `performance_schema` | `1` | Required for query metrics, samples, and activity |
  | `max_digest_length` | `4096` | Larger captured SQL text |
  | `performance_schema_max_digest_length` | `4096` | Match `max_digest_length` |
  | `performance_schema_max_sql_text_length` | `4096` | Larger captured SQL text |

  Changing `performance_schema` requires an RDS reboot.

- **The MySQL `datadog` user** created on the database — see *Manual SQL* below.
- A **Datadog API key** for the destination org.
- (Optional) An **existing ECS cluster** in the target region. By default this template provisions a new cluster named `${name_prefix}-cluster`; set `existing_ecs_cluster_name` to attach the agent service to a cluster you already operate (recommended when you already run other Fargate services in the account).

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
# fill in vpc_id, subnet_ids, db_security_group_id, db_endpoint,
# datadog_user_password, datadog_api_key, and any optional overrides

terraform init
terraform plan
terraform apply
```

`terraform apply` creates ~7 resources: ECS cluster (skipped if `existing_ecs_cluster_name` is set), task definition, service, task security group, ingress rule on the database's SG, IAM execution role (+ attachment), CloudWatch log group.

## Verify

1. Service is healthy:
   ```bash
   aws ecs describe-services \
     --cluster $(terraform output -raw ecs_cluster_name) \
     --services $(terraform output -raw ecs_service_name) \
     --query 'services[0].{running:runningCount,desired:desiredCount,events:events[0:3]}'
   ```
2. Tail the agent logs and look for the `[mysql]` check running cleanly:
   ```bash
   aws logs tail $(terraform output -raw log_group_name) --follow
   ```
   You should see lines like `Running check mysql` and no `performance_schema` errors.
3. In the Datadog UI:
   - **Infrastructure → Containers**: the `datadog-agent` container appears.
   - **Databases → List**: the MySQL host appears with DBM enabled.
   - **Databases → Query Metrics**: rows render within ~2 minutes of database traffic.

## Teardown

```bash
terraform destroy
```

Removes the ECS resources and the ingress rule we added to the database's SG. The database, the VPC, and the MySQL `datadog` user are untouched. If you supplied `existing_ecs_cluster_name`, that cluster is also untouched (only the service we created on it is removed).

## Security note

The `datadog_user_password` is passed straight into the ECS task definition (Autodiscovery labels). Anyone with `ecs:DescribeTaskDefinition` on this account can read it. This is fine for a demo; for production, switch to **AWS Secrets Manager**:

1. Store the password in a secret.
2. Add `secretsmanager:GetSecretValue` to the execution role for that secret's ARN.
3. Inject as `DD_MYSQL_PASSWORD` via `secrets[]` on the container.
4. Reference in the AD instance as `password = "%%env_DD_MYSQL_PASSWORD%%"`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent logs show `connection refused` to the database | Database SG ingress rule didn't apply, or task is in a subnet with no route to the database |
| Agent logs show `performance_schema is disabled` | Parameter group missing `performance_schema=1`, or RDS not rebooted after the change |
| Agent logs show `Access denied for user 'datadog'` | Manual SQL not run, or grants missing |
| `query_metrics` empty but check is running | `events_statements_*` consumers not enabled in `performance_schema.setup_consumers` |
| `query_samples` empty | `datadog.explain_statement` procedure not created, or `EXECUTE` not granted on `datadog.*` |
| No data in Datadog UI | API key wrong, `DD_SITE` mismatched, or task can't reach `*.${DD_SITE}` (NAT egress missing) |

## Files

- `versions.tf` — Terraform + provider pins
- `variables.tf` — inputs (secrets marked `sensitive`)
- `main.tf` — ECS cluster, task def, service, IAM, SG, log group
- `outputs.tf` — useful identifiers for verification
- `terraform.tfvars.example` — fill-in-the-blanks template
