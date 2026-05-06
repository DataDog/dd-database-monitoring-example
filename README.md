# dd-database-monitoring-example

Worked examples for [Datadog Database Monitoring](https://docs.datadoghq.com/database_monitoring/). Two flavors, depending on what you want to do:

| If you want to… | Use |
|---|---|
| **Try DBM end-to-end on your laptop in a few minutes** — spin up a database, the Datadog Agent, and a load generator, all in containers | The Docker Compose examples at the repo root (see below) |
| **Provision the Datadog Agent for a real, existing database** — RDS, Cloud SQL, AlloyDB, etc. | The Terraform examples in [`terraform/`](./terraform/) |

## Docker Compose examples (laptop / quick try)

Backs the [Getting Started with Database Monitoring](https://docs.datadoghq.com/getting_started/database_monitoring/) docs.

```bash
export DD_API_KEY=...

# Postgres + Datadog Agent + pgbench load
make postgres

# MySQL + Datadog Agent + sysbench load
make mysql

make clean
```

Files: `docker-compose-postgres.yaml`, `docker-compose-mysql.yaml`, `postgres/`, `mysql/`, `Makefile`.

## Terraform examples (production-style deploy)

Backs the [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page. Each example provisions only the **Datadog Agent** for a specific combination of database + hosting + agent runtime — you bring the database.

Layout mirrors the docs filters:

```
terraform/<database>/<hosting>/<agent-runtime>/
```

Available today:

| Database | Hosting | Agent runtime | Path |
|---|---|---|---|
| Postgres | RDS | ECS Fargate | [`terraform/postgres/rds/ecs-fargate/`](./terraform/postgres/rds/ecs-fargate/) |
| Postgres | RDS | Amazon EKS (EC2 nodes) | [`terraform/postgres/rds/amazon-eks/`](./terraform/postgres/rds/amazon-eks/) |

See [`terraform/README.md`](./terraform/README.md) for the full list of filter values, conventions across examples, and what's coming.
