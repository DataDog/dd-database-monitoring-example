# Terraform examples for Datadog Database Monitoring

These examples back the [**Set up Database Monitoring with Terraform**](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page. Each example provisions the **Datadog Agent** for DBM against an **existing database** — the database itself, the VPC, and the in-database `datadog` user are prerequisites you bring (or bootstrap separately; see [`_bootstrap/`](./_bootstrap/)).

## Layout

Examples are organized by the same three filters as the docs page:

```
terraform/<database>/<hosting>/<agent-runtime>/
```

| Filter | Values used today |
|---|---|
| `<database>` | `postgres`, `mysql` *(coming soon)*, `sql_server` *(coming soon)* |
| `<hosting>` | `rds`, `aurora` *(coming soon)*, `cloud_sql` *(coming soon)*, `alloydb` *(coming soon)*, `azure` *(coming soon)*, `self-hosted` *(coming soon)* |
| `<agent-runtime>` | `ecs-fargate`, `amazon-eks`, `ecs-ec2` *(coming soon)*, `amazon-ec2` *(coming soon)* |

## Available today

| Database | Hosting | Agent runtime | Path |
|---|---|---|---|
| Postgres | RDS | ECS Fargate | [`postgres/rds/ecs-fargate/`](./postgres/rds/ecs-fargate/) |
| Postgres | RDS | Amazon EKS (EC2 nodes) | [`postgres/rds/amazon-eks/`](./postgres/rds/amazon-eks/) |

Combinations not in this table render a "Coming soon" stub on the docs page; in this repo they simply have no directory yet.

## How to use an example

Each example directory is a self-contained Terraform module:

```bash
cd terraform/postgres/rds/ecs-fargate

cp terraform.tfvars.example terraform.tfvars
# fill in the variables — see the README in that directory for the full list

terraform init
terraform plan
terraform apply
```

Every example follows the same file convention:

| File | Purpose |
|---|---|
| `versions.tf` | Terraform + provider version pins |
| `variables.tf` | Inputs (secrets are marked `sensitive`) |
| `main.tf` | Resources |
| `outputs.tf` | Useful identifiers for verification |
| `terraform.tfvars.example` | Fill-in-the-blanks template |
| `README.md` | Architecture, prerequisites, apply, verify, troubleshooting |
| `.gitignore` | Excludes `*.tfvars`, state, plan files |

## Conventions across all examples

- **No database is provisioned.** You bring the RDS/Cloud SQL/etc. instance.
- **The Postgres `datadog` user is created out-of-band.** Each example's README has the exact SQL to run against your database.
- **Secrets land in Terraform state.** Examples mark `sensitive` on inputs and document the production hardening path (Secrets Manager, External Secrets Operator, etc.) in each README's *Security note* section.
- **Terraform >= 1.5** and the relevant cloud provider CLI authenticated.
- **`terraform destroy` is reversible for the agent side only.** Your database, VPC, and the in-database `datadog` user are never touched.

## See also

- [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) — the docs page these examples back
- [Database Monitoring](https://docs.datadoghq.com/database_monitoring/) — DBM product overview
- [`_bootstrap/`](./_bootstrap/) — Terraform for the prerequisites these examples assume (RDS instance with DBM-ready parameter group, the `datadog` Postgres user, etc.)
