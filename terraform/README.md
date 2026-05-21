# Terraform examples for Datadog Database Monitoring

These examples back the [**Set up Database Monitoring with Terraform**](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page. Each example provisions the **Datadog Agent** for DBM against an **existing database** — the database itself, the VPC, and the in-database `datadog` user are prerequisites you bring (or bootstrap separately; see [`_bootstrap/`](./_bootstrap/)).

## Layout

```
terraform/<database>/<cloud>/<agent-runtime>/
```

The directory tree is organized by **cloud**, since one Terraform module typically covers all of a cloud's database hosting flavors that share the same VPC + security-group semantics. The docs page filters customers by hosting (`rds`, `aurora`, `cloud_sql`, `alloydb`, `azure`, `self_hosted`) and points multiple filter values at the same directory when one module covers them.

| Slot | Values used today | Maps to docs `db_hosting` filter |
|---|---|---|
| `<database>` | `postgres`, `mysql` | `database` |
| `<cloud>` | `aws` | `rds`, `aurora`, `self_hosted` (when self-hosted on EC2 in the same VPC) |
| `<agent-runtime>` | `ecs-fargate`, `amazon-eks`, `ec2` | `agent_runtime` |

## Available today

| Database | Cloud | Agent runtime | Path | Covers `db_hosting` |
|---|---|---|---|---|
| Postgres | AWS | ECS Fargate | [`postgres/aws/ecs-fargate/`](./postgres/aws/ecs-fargate/) | `rds`, `aurora`, `self_hosted` (on EC2) |
| Postgres | AWS | Amazon EKS (EC2 nodes) | [`postgres/aws/amazon-eks/`](./postgres/aws/amazon-eks/) | `rds`, `aurora`, `self_hosted` (on EC2) |
| Postgres | AWS | EC2 | [`postgres/aws/ec2/`](./postgres/aws/ec2/) | `rds`, `aurora`, `self_hosted` (on EC2) |
| MySQL | AWS | ECS Fargate | [`mysql/aws/ecs-fargate/`](./mysql/aws/ecs-fargate/) | `rds`, `aurora`, `self_hosted` (on EC2) |
| MySQL | AWS | Amazon EKS (EC2 nodes) | [`mysql/aws/amazon-eks/`](./mysql/aws/amazon-eks/) | `rds`, `aurora`, `self_hosted` (on EC2) |
| MySQL | AWS | EC2 | [`mysql/aws/ec2/`](./mysql/aws/ec2/) | `rds`, `aurora`, `self_hosted` (on EC2) |

Combinations not in this table render a "Coming soon" stub on the docs page; in this repo they simply have no directory yet.

## How to use an example

Each example directory is a self-contained Terraform module:

```bash
cd terraform/postgres/aws/ecs-fargate

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
- **The `datadog` database user is created out-of-band.** Each example's README has the exact SQL to run against your database.
- **Secrets land in Terraform state.** Examples mark `sensitive` on inputs and document the production hardening path (Secrets Manager, External Secrets Operator, etc.) in each README's *Security note* section.
- **Terraform >= 1.5** and the relevant cloud provider CLI authenticated.
- **`terraform destroy` is reversible for the agent side only.** Your database, VPC, and the in-database `datadog` user are never touched.

## See also

- [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) — the docs page these examples back
- [Database Monitoring](https://docs.datadoghq.com/database_monitoring/) — DBM product overview
- [`_bootstrap/`](./_bootstrap/) — Terraform for the prerequisites these examples assume (RDS instance with DBM-ready parameter group, the `datadog` database user, etc.)
