# DBM on ECS Fargate — Postgres (RDS)

Stands up a single Datadog Agent on **AWS ECS Fargate** with **Database Monitoring** enabled, configured to monitor an **existing AWS RDS Postgres** instance via Autodiscovery.

This is a bring-your-own-DB setup: it does **not** provision an RDS instance, a VPC, or the Postgres `datadog` user. It only deploys the agent into the VPC where your RDS already lives, and opens the right ingress on the RDS security group.

This example backs the **Postgres + RDS + ECS Fargate** combination on the [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page.

## Architecture

```
   ┌────────────────────────── existing VPC ──────────────────────────┐
   │                                                                  │
   │   private subnet (with NAT egress)            ┌──────────────┐   │
   │   ┌────────────────────────┐    5432          │     RDS      │   │
   │   │  Fargate task          │ ───────────────▶ │   Postgres   │   │
   │   │  datadog/agent:7       │                  └──────────────┘   │
   │   │  ECS_FARGATE=true      │                                     │
   │   │  AD: postgres + dbm    │                                     │
   │   └─────────┬──────────────┘                                     │
   │             │ NAT egress                                         │
   └─────────────┼────────────────────────────────────────────────────┘
                 ▼
            Datadog (DD_SITE)
```

## Prerequisites

- **Terraform >= 1.5** and AWS credentials with permission to create ECS, IAM, security groups, and CloudWatch log groups in the target region.
- **An existing RDS Postgres** instance (Postgres 10+).
- **A private subnet in the RDS's VPC** that already has NAT egress to the internet (the agent must reach `*.${DD_SITE}`).
- **RDS parameter group** with the following parameters set:

  | Parameter | Value | Why |
  |---|---|---|
  | `shared_preload_libraries` | `pg_stat_statements` | Required for query metrics |
  | `track_activity_query_size` | `4096` | Increases captured SQL text size |
  | `pg_stat_statements.track` | `ALL` | Tracks statements inside functions/procs |
  | `pg_stat_statements.max` | `10000` | More normalized queries retained |
  | `pg_stat_statements.track_utility` | `off` | Skip PREPARE/EXPLAIN noise |

  Changing `shared_preload_libraries` requires an RDS reboot.

- **The Postgres `datadog` user** created on the RDS instance — see *Manual SQL* below.
- A **Datadog API key** for the destination org.
- (Optional) An **existing ECS cluster** in the target region. By default this template provisions a new cluster named `${name_prefix}-cluster`; set `existing_ecs_cluster_name` to attach the agent service to a cluster you already operate (recommended when you already run other Fargate services in the account).

## Manual SQL

Run this once against the RDS instance using a role with `rds_superuser` (the RDS master). Repeat the schema/grants block **in every database** you want monitored.

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
# fill in vpc_id, subnet_ids, rds_security_group_id, rds_endpoint,
# database_name, datadog_user_password, datadog_api_key, …

terraform init
terraform plan
terraform apply
```

`terraform apply` creates ~7 resources: ECS cluster (skipped if `existing_ecs_cluster_name` is set), task definition, service, task security group, RDS-side ingress rule, IAM execution role (+ attachment), CloudWatch log group.

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
   - **Databases → List**: the RDS host appears with DBM enabled.
   - **Databases → Query Metrics**: rows render within ~2 minutes of database traffic.

## Teardown

```bash
terraform destroy
```

Removes the ECS resources and the ingress rule we added to the RDS SG. The RDS instance, VPC, and the Postgres `datadog` user are untouched. If you supplied `existing_ecs_cluster_name`, that cluster is also untouched (only the service we created on it is removed).

## Security note

The `datadog_user_password` is passed straight into the ECS task definition (Autodiscovery labels). Anyone with `ecs:DescribeTaskDefinition` on this account can read it. This is fine for a demo; for production, switch to **AWS Secrets Manager**:

1. Store the password in a secret.
2. Add `secretsmanager:GetSecretValue` to the execution role for that secret's ARN.
3. Inject as `DD_POSTGRES_PASSWORD` via `secrets[]` on the container.
4. Reference in the AD instance as `password = "%%env_DD_POSTGRES_PASSWORD%%"`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent logs show `connection refused` to RDS | RDS SG ingress rule didn't apply, or task is in a subnet with no route to RDS |
| Agent logs show `pg_stat_statements is not loaded` | RDS parameter group missing `shared_preload_libraries=pg_stat_statements`, or RDS not rebooted |
| Agent logs show `permission denied for relation pg_stat_activity` | `pg_monitor` role not granted to `datadog` user |
| No data in Datadog UI | API key wrong, `DD_SITE` mismatched, or task can't reach `*.${DD_SITE}` (NAT egress missing) |
| `query_samples` empty | `datadog.explain_statement` function not created in the monitored database |

## Files

- `versions.tf` — Terraform + provider pins
- `variables.tf` — inputs (secrets marked `sensitive`)
- `main.tf` — ECS cluster, task def, service, IAM, SG, log group
- `outputs.tf` — useful identifiers for verification
- `terraform.tfvars.example` — fill-in-the-blanks template
