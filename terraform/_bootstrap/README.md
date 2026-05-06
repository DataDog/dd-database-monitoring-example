# Bootstrap Terraform

Terraform for the prerequisites the agent-install examples in [`../`](../) assume: a running database with the right parameters, and the in-database `datadog` user.

The agent-install examples deliberately don't create these — most customers already have an RDS/Cloud SQL/etc. instance and want to drop the agent next to it. Use the modules here when you're starting from a blank account and want a one-shot way to stand up a DBM-ready database for testing.

## Status

Empty for now. Modules will land here as they're written. Planned candidates:

- `rds-postgres-with-dbm-params/` — RDS Postgres + parameter group with `pg_stat_statements` and the rest of the DBM-required parameters set, ready for one of the agent-install examples to point at.
- `rds-postgres-datadog-user/` — runs the `CREATE USER datadog` + `pg_stat_statements` extension + `datadog.explain_statement` function via a one-shot Lambda (or the AWS RDS Data API), so the manual SQL step in each example README becomes optional.
- `vpc-with-nat/` — minimal VPC with public + private subnets and a NAT gateway, suitable as the network for any of the agent-install examples in greenfield testing.

If you have a use case that fits here, open an issue or PR.
