# dd-database-monitoring-example

Worked examples for [Datadog Database Monitoring](https://docs.datadoghq.com/database_monitoring/). Two flavors, depending on what you want to do:

| If you want to… | Use |
|---|---|
| **Try DBM end-to-end on your laptop in a few minutes** — spin up a database, the Datadog Agent, and a load generator, all in containers | The Docker Compose examples at the repo root (see below) |
| **Provision the Datadog Agent for a real, existing database** — RDS, Cloud SQL, AlloyDB, etc. | The Terraform examples in [`terraform/`](./terraform/) |

## Docker Compose examples (laptop / quick try)

Backs the [Getting Started with Database Monitoring](https://docs.datadoghq.com/getting_started/database_monitoring/) docs.

Each stack starts three containers:

| Container | What it does |
|---|---|
| `postgres` / `mysql` | Database pre-configured for DBM (extensions, users, explain functions) |
| `agent` | Datadog Agent with DBM + APM enabled, auto-discovers the database via Docker labels |
| `app` | Go orders app — seeds an e-commerce schema and runs continuous queries to generate realistic DBM signals |

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker + Docker Compose v2)
- A Datadog API key

### Quick start

```bash
export DD_API_KEY=<your-api-key>

# Postgres 14 + Datadog Agent + orders app
make postgres

# MySQL 8.0 + Datadog Agent + orders app
make mysql

# Tear down
make clean
```

For non-US Datadog sites set `DD_SITE` before running:

```bash
export DD_SITE=datadoghq.eu   # EU
export DD_SITE=datad0g.com    # staging
```

### What you'll see in Datadog

Navigate to **[Database Monitoring](https://app.datadoghq.com/databases)** → **Queries**. The database instance appears within ~2 minutes of startup.

The orders app generates these DBM signals continuously:

| Signal | How it's produced |
|---|---|
| Query metrics | SELECT / INSERT / UPDATE across `users`, `orders`, `order_items` |
| Execution plans | `explain_statement` function called automatically by the agent |
| Full table scans | Queries on `orders.status` (intentionally un-indexed) |
| Lock contention | Two goroutines compete for the same rows via `SELECT FOR UPDATE` |
| APM ↔ DBM correlation | Trace context injected into every SQL query — click a span in APM to jump to the matching query in DBM |

Files: `docker-compose-postgres.yaml`, `docker-compose-mysql.yaml`, `postgres/`, `mysql/`, `app/`, `Makefile`.

## Terraform examples (production-style deploy)

Backs the [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page. Each example provisions only the **Datadog Agent** for a specific combination of database + hosting + agent runtime — you bring the database.

Layout mirrors the docs filters:

```
terraform/<database>/<hosting>/<agent-runtime>/
```

Available today:

| Database | Hosting | Agent runtime | Path |
|---|---|---|---|
| Postgres | RDS | ECS Fargate | [`terraform/postgres/aws/ecs-fargate/`](./terraform/postgres/aws/ecs-fargate/) |
| Postgres | RDS | Amazon EKS (EC2 nodes) | [`terraform/postgres/aws/amazon-eks/`](./terraform/postgres/aws/amazon-eks/) |
| Postgres | RDS | EC2 | [`terraform/postgres/aws/ec2/`](./terraform/postgres/aws/ec2/) |

See [`terraform/README.md`](./terraform/README.md) for the full list of filter values, conventions across examples, and what's coming.
