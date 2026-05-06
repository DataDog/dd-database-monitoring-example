# DBM on ECS Fargate — Postgres in AWS

Stands up a single Datadog Agent on **AWS ECS Fargate** with **Database Monitoring** enabled, configured to monitor an **existing Postgres database in AWS** via Autodiscovery.

This is a bring-your-own-DB setup: it does **not** provision the database, a VPC, or the Postgres `datadog` user. It only deploys the agent into the VPC where your Postgres already lives, and opens the right ingress on the database's security group.

This example backs the **Postgres + ECS Fargate** combination on the [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page, for `db_hosting` ∈ {`rds`, `aurora`, `self_hosted`}.

## Hosting coverage

This module works for any Postgres database reachable inside an AWS VPC by security group. Point `db_endpoint` and `db_security_group_id` at:

- **Amazon RDS Postgres** — the RDS endpoint and the RDS security group.
- **Amazon Aurora Postgres** — the Aurora cluster writer endpoint and the Aurora cluster's security group.
- **Self-hosted Postgres on EC2 in the same VPC** — the EC2 instance hostname/IP and the security group attached to the Postgres EC2 instance.

For Postgres self-hosted **outside AWS** (on-premises, in another cloud), this AWS-side example does not apply.

## Architecture

```
   ┌────────────────────────── existing VPC ──────────────────────────┐
   │                                                                  │
   │   private subnet (with NAT egress)            ┌──────────────┐   │
   │   ┌────────────────────────┐    5432          │   Postgres   │   │
   │   │  Fargate task          │ ───────────────▶ │  (RDS, or    │   │
   │   │  datadog/agent:7       │                  │   Aurora, or │   │
   │   │  ECS_FARGATE=true      │                  │   self-      │   │
   │   │  AD: postgres + dbm    │                  │   hosted EC2)│   │
   │   └─────────┬──────────────┘                  └──────────────┘   │
   │             │ NAT egress                                         │
   └─────────────┼────────────────────────────────────────────────────┘
                 ▼
            Datadog (DD_SITE)
```

## Prerequisites

- **Terraform >= 1.5** and AWS credentials with permission to create ECS, IAM, security groups, and CloudWatch log groups in the target region.
- **An existing Postgres database** (Postgres 10+) — RDS, Aurora, or self-hosted on EC2.
- **A private subnet in the database's VPC** that already has NAT egress to the internet (the agent must reach `*.${DD_SITE}`).
- **A parameter group (RDS/Aurora) or `postgresql.conf` (self-hosted)** with the following parameters set:

  | Parameter | Value | Why |
  |---|---|---|
  | `shared_preload_libraries` | `pg_stat_statements` | Required for query metrics |
  | `track_activity_query_size` | `4096` | Increases captured SQL text size |
  | `pg_stat_statements.track` | `ALL` | Tracks statements inside functions/procs |
  | `pg_stat_statements.max` | `10000` | More normalized queries retained |
  | `pg_stat_statements.track_utility` | `off` | Skip PREPARE/EXPLAIN noise |

  Changing `shared_preload_libraries` requires a database restart (for RDS/Aurora, an instance reboot).

- **The Postgres `datadog` user** created on the database — see *Manual SQL* below.
- A **Datadog API key** for the destination org.
- (Optional) An **existing ECS cluster** in the target region. By default this template provisions a new cluster named `${name_prefix}-cluster`; set `existing_ecs_cluster_name` to attach the agent service to a cluster you already operate (recommended when you already run other Fargate services in the account).

## Manual SQL

Run this once against the Postgres database using a superuser role (`rds_superuser` on RDS/Aurora, or any role with `SUPERUSER` on self-hosted). Repeat the schema/grants block **in every database** you want monitored.

```sql
-- Create the role
CREATE USER datadog WITH password '<PASSWORD>';
ALTER ROLE datadog INHERIT;

-- Per-database grants and extension (Postgres ≥ 10)
CREATE SCHEMA datadog;
GRANT USAGE ON SCHEMA datadog TO datadog;
GRANT USAGE ON SCHEMA public TO datadog;
GRANT pg_monitor TO datadog;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;

-- Required for explain plan collection
CREATE OR REPLACE FUNCTION datadog.explain_statement(
   l_query TEXT,
   OUT explain JSON
)
RETURNS SETOF JSON AS
$$
DECLARE
  curs REFCURSOR;
  plan JSON;
BEGIN
  SET TRANSACTION READ ONLY;
  OPEN curs FOR EXECUTE pg_catalog.concat('EXPLAIN (FORMAT JSON) ', l_query);
  FETCH curs INTO plan;
  CLOSE curs;
  RETURN QUERY SELECT plan;
END;
$$
LANGUAGE 'plpgsql'
RETURNS NULL ON NULL INPUT
SECURITY DEFINER;
```

Reference: [Setup DBM for Postgres on RDS](https://docs.datadoghq.com/database_monitoring/setup_postgres/rds/).

## Apply

```bash
cp terraform.tfvars.example terraform.tfvars
# fill in vpc_id, subnet_ids, db_security_group_id, db_endpoint,
# database_name, datadog_user_password, datadog_api_key, …

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
2. Tail the agent logs and look for the `[postgres]` check running cleanly:
   ```bash
   aws logs tail $(terraform output -raw log_group_name) --follow
   ```
   You should see lines like `Running check postgres` and no `dbm` or `pg_stat_statements` errors.
3. In the Datadog UI:
   - **Infrastructure → Containers**: the `datadog-agent` container appears.
   - **Databases → List**: the Postgres host appears with DBM enabled.
   - **Databases → Query Metrics**: rows render within ~2 minutes of database traffic.

## Teardown

```bash
terraform destroy
```

Removes the ECS resources and the ingress rule we added to the database's SG. The database, the VPC, and the Postgres `datadog` user are untouched. If you supplied `existing_ecs_cluster_name`, that cluster is also untouched (only the service we created on it is removed).

## Security note

The `datadog_user_password` is passed straight into the ECS task definition (Autodiscovery labels). Anyone with `ecs:DescribeTaskDefinition` on this account can read it. This is fine for a demo; for production, switch to **AWS Secrets Manager**:

1. Store the password in a secret.
2. Add `secretsmanager:GetSecretValue` to the execution role for that secret's ARN.
3. Inject as `DD_POSTGRES_PASSWORD` via `secrets[]` on the container.
4. Reference in the AD instance as `password = "%%env_DD_POSTGRES_PASSWORD%%"`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent logs show `connection refused` to the database | Database SG ingress rule didn't apply, or task is in a subnet with no route to the database |
| Agent logs show `pg_stat_statements is not loaded` | Parameter group / `postgresql.conf` missing `shared_preload_libraries=pg_stat_statements`, or the database wasn't restarted |
| Agent logs show `permission denied for relation pg_stat_activity` | `pg_monitor` role not granted to `datadog` user |
| No data in Datadog UI | API key wrong, `DD_SITE` mismatched, or task can't reach `*.${DD_SITE}` (NAT egress missing) |
| `query_samples` empty | `datadog.explain_statement` function not created in the monitored database |

## Files

- `versions.tf` — Terraform + provider pins
- `variables.tf` — inputs (secrets marked `sensitive`)
- `main.tf` — ECS cluster, task def, service, IAM, SG, log group
- `outputs.tf` — useful identifiers for verification
- `terraform.tfvars.example` — fill-in-the-blanks template
