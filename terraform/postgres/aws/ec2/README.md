# DBM on EC2 -- Postgres in AWS

Stands up a single Datadog Agent on an **AWS EC2** instance with **Database Monitoring** enabled, configured to monitor an **existing Postgres database in AWS**.

This is a bring-your-own-DB setup: it does **not** provision the database, a VPC, or the Postgres `datadog` user. It only deploys the agent into the VPC where your Postgres already lives, and opens the right ingress on the database's security group.

This example backs the **Postgres + EC2** combination on the [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page, for `db_hosting` ∈ {`rds`, `aurora`, `self_hosted`}. Companion to [`../ecs-fargate/`](../ecs-fargate/) and [`../amazon-eks/`](../amazon-eks/), which do the same thing on ECS Fargate and EKS.

## Hosting coverage

This module works for any Postgres database reachable inside an AWS VPC by security group. Point `db_endpoint` and `db_security_group_id` at:

- **Amazon RDS Postgres** -- the RDS endpoint and the RDS security group.
- **Amazon Aurora Postgres** -- the Aurora cluster writer endpoint and the Aurora cluster's security group.
- **Self-hosted Postgres on EC2 in the same VPC** -- the EC2 instance hostname/IP and the security group attached to the Postgres EC2 instance.

For Postgres self-hosted **outside AWS** (on-premises, in another cloud), this AWS-side example does not apply.

## Architecture

```
   ┌────────────────────── existing VPC ──────────────────────┐
   │                                                          │
   │   chosen subnet (public for SSH, or private + SSM)       │
   │   ┌────────────────────────┐    5432    ┌──────────────┐ │
   │   │  EC2 (Amazon Linux 23) │ ─────────▶ │   Postgres   │ │
   │   │  docker run            │            │  (RDS, or    │ │
   │   │  datadog/agent:7       │            │   Aurora, or │ │
   │   │  postgres.d/conf.yaml  │            │   self-      │ │
   │   └─────────┬──────────────┘            │   hosted EC2)│ │
   │             │ outbound                  └──────────────┘ │
   └─────────────┼──────────────────────────────────────────-─┘
                 ▼
            Datadog (DD_SITE)
```

## Prerequisites

- **Terraform >= 1.5** and AWS credentials with permission to create EC2, IAM, and security groups in the target region.
- **An existing Postgres database** (Postgres 10+) -- RDS, Aurora, or self-hosted on EC2.
- **A subnet in the database's VPC** with internet egress (IGW for a public subnet, NAT for a private one) so the agent can reach `*.${DD_SITE}` and pull the agent image.
- **A parameter group (RDS/Aurora) or `postgresql.conf` (self-hosted)** with the following parameters set:

  | Parameter | Value | Why |
  |---|---|---|
  | `shared_preload_libraries` | `pg_stat_statements` | Required for query metrics |
  | `track_activity_query_size` | `4096` | Increases captured SQL text size |
  | `pg_stat_statements.track` | `ALL` | Tracks statements inside functions/procs |
  | `pg_stat_statements.max` | `10000` | More normalized queries retained |
  | `pg_stat_statements.track_utility` | `off` | Skip PREPARE/EXPLAIN noise |

  Changing `shared_preload_libraries` requires a database restart (for RDS/Aurora, an instance reboot).

- **The Postgres `datadog` user** created on the database -- see *Manual SQL* below.
- A **Datadog API key** for the destination org.
- (Optional) An existing **EC2 key pair** if you want to SSH in for verification -- otherwise leave `key_pair_name = ""` and use SSM Session Manager.

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
# fill in vpc_id, subnet_id, db_security_group_id, db_endpoint,
# database_name, datadog_user_password, datadog_api_key,
# key_pair_name, ssh_ingress_cidrs, ...

terraform init
terraform plan
terraform apply
```

`terraform apply` creates ~7 resources: EC2 instance, host security group, ingress rule on the database's SG, IAM role + SSM policy attachment + instance profile.

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
   docker logs datadog-agent | grep -E '(postgres|dbm)' | tail -50
   ```
   You should see `Running check postgres` and no `pg_stat_statements` errors.
4. In the Datadog UI:
   - **Infrastructure → Hosts**: the EC2 host appears.
   - **Databases → List**: the Postgres host appears with DBM enabled.
   - **Databases → Query Metrics**: rows render within ~2 minutes of database traffic.

## Teardown

```bash
terraform destroy
```

Removes the EC2 instance, host SG, IAM role, and the ingress rule we added to the database's SG. The database, the VPC, and the Postgres `datadog` user are untouched.

## Security note

The `datadog_user_password` is rendered into `/etc/datadog-agent/conf.d/postgres.d/conf.yaml` on the host via `user_data` (cloud-init). EC2 user_data is readable by anyone with `ec2:DescribeInstanceAttribute` on the instance, and the rendered file is readable by anyone with shell access. This is fine for a demo; for production, switch to **AWS Secrets Manager** + a small fetch script in `user_data`, or move to ECS Fargate (`../ecs-fargate/`) with `secrets[]`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Agent logs show `connection refused` to the database | Database SG ingress rule didn't apply, or instance is in a subnet with no route to the database |
| Agent logs show `pg_stat_statements is not loaded` | Parameter group / `postgresql.conf` missing `shared_preload_libraries=pg_stat_statements`, or the database wasn't restarted |
| Agent logs show `permission denied for relation pg_stat_activity` | `pg_monitor` role not granted to `datadog` user |
| No data in Datadog UI | API key wrong, `DD_SITE` mismatched, or instance can't reach `*.${DD_SITE}` (no IGW/NAT egress) |
| `query_samples` empty | `datadog.explain_statement` function not created in the monitored database |
| `docker: command not found` on first SSH | `user_data` still running -- wait ~60s and re-check with `cloud-init status --wait` |

## Files

- `versions.tf` -- Terraform + provider pins
- `variables.tf` -- inputs (secrets marked `sensitive`)
- `main.tf` -- EC2 instance, IAM role, security group, database ingress rule
- `user_data.sh.tpl` -- cloud-init script: installs Docker, drops conf.yaml, runs the agent
- `outputs.tf` -- useful identifiers for verification
- `terraform.tfvars.example` -- fill-in-the-blanks template
