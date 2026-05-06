# DBM on Amazon EKS (EC2 node groups) — Postgres (RDS)

Stands up the Datadog Agent on an **AWS EKS cluster with EC2 node groups** with **Database Monitoring** enabled, configured to monitor an **existing AWS RDS Postgres** instance via a **cluster check**.

This example backs the **Postgres + RDS + Amazon EKS** combination on the [Set up Database Monitoring with Terraform](https://docs.datadoghq.com/database_monitoring/setup_agent_terraform/) docs page. Companion to [`../ecs-fargate/`](../ecs-fargate/), which does the same thing on ECS Fargate.

Supports two modes — pick one:

- **Bring your own EKS cluster (default).** Set `eks_cluster_name` and `eks_node_security_group_id` in `terraform.tfvars`. The template installs the Datadog Helm chart into your cluster, opens 5432 ingress on the RDS SG from the node SG, and creates ~3 resources. Apply takes ~3 minutes.
- **Provision a new EKS cluster (greenfield).** Leave `eks_cluster_name` empty and supply `private_subnet_ids` instead. The template provisions an EKS cluster + managed node group + IAM, then installs the agent. ~13 resources, ~15-20 minute apply, **adds ongoing AWS cost — see [Cost](#cost) below**.

Either way, this template does **not** provision the RDS instance, the VPC, or the Postgres `datadog` user. The Postgres check runs on the Cluster Check Runner pods so DBM data is emitted once cluster-wide, not per node.

## Cost

If you are **bringing your own EKS cluster**, this template adds **no AWS cost** — only a single security-group rule, a Kubernetes namespace, and a Helm release.

If you are **provisioning a new EKS cluster** via this template, the new infrastructure has ongoing cost regardless of utilization:

| Component | Cost (us-east-1, on-demand) |
|---|---|
| EKS control plane | **$0.10/hr (~$73/month)** — billed continuously while the cluster exists, even when idle |
| Managed node group EC2 instances | `node_desired_count` × instance hourly rate. Default `t3.small` × 2 ≈ $0.04/hr (~$30/month). |
| EBS gp3 volumes attached to nodes | `node_desired_count` × `node_disk_size_gb` × $0.08/GB-month. Default 2 × 20 GiB ≈ $3/month. |
| Network egress, NAT, EIPs | depends on traffic |

**Order-of-magnitude total for the greenfield default**: ~$110/month (~$3.60/day).

This is meant for a one-off setup or a long-lived demo cluster. If you only need DBM for a few hours of testing, run `terraform destroy` when you're done — destroy in greenfield mode tears down the EKS cluster and the node group along with the agent install (see [Teardown](#teardown)).

If you already operate EKS for other workloads, **always prefer BYO mode** — there is no reason to spin up a second cluster just for DBM.

## Architecture

```
   ┌────────────────────────── existing VPC ──────────────────────────┐
   │                                                                  │
   │   EKS cluster (EC2 node groups)               ┌──────────────┐   │
   │   ┌────────────────────────┐    5432          │     RDS      │   │
   │   │  Cluster Check Runner  │ ───────────────▶ │   Postgres   │   │
   │   │  datadog/agent:7       │                  └──────────────┘   │
   │   │  postgres check        │                                     │
   │   │  cluster_check: true   │                                     │
   │   └─────────┬──────────────┘                                     │
   │             │                                                    │
   │   ┌─────────┴──────────────┐                                     │
   │   │  Cluster Agent         │                                     │
   │   │  dispatches checks     │                                     │
   │   └─────────┬──────────────┘                                     │
   │             │                                                    │
   │   ┌─────────┴──────────────┐                                     │
   │   │  node Agent DaemonSet  │ (host metrics, kube checks)         │
   │   └─────────┬──────────────┘                                     │
   │             │ egress (NAT or VPC endpoint)                       │
   └─────────────┼────────────────────────────────────────────────────┘
                 ▼
            Datadog (DD_SITE)
```

## Prerequisites

### For both modes

- **Terraform >= 1.5** with the `aws`, `helm`, and `kubernetes` providers.
- **An existing RDS Postgres** instance (Postgres 10+) in a VPC reachable from the EKS nodes.
- **The Postgres `datadog` user** created on the RDS instance — see *Manual SQL* below.
- A **Datadog API key** for the destination org (and an app key if you want Cluster Agent features beyond DBM).
- **RDS parameter group** with the following parameters set:

  | Parameter | Value | Why |
  |---|---|---|
  | `shared_preload_libraries` | `pg_stat_statements` | Required for query metrics |
  | `track_activity_query_size` | `4096` | Increases captured SQL text size |
  | `pg_stat_statements.track` | `ALL` | Tracks statements inside functions/procs |
  | `pg_stat_statements.max` | `10000` | More normalized queries retained |
  | `pg_stat_statements.track_utility` | `off` | Skip PREPARE/EXPLAIN noise |

  Changing `shared_preload_libraries` requires an RDS reboot.

### Additionally for BYO mode

- **AWS credentials** with permission to create security-group rules and to call `eks:DescribeCluster` / `eks:GetToken` for the target cluster, plus `kubectl`-equivalent permissions inside the cluster (typically the same IAM principal mapped via `aws-auth` or an EKS access entry).
- **An existing EKS cluster with EC2 node groups**. The node group's security group ID is required.
- **Cluster networking** that lets the worker nodes reach `*.${DD_SITE}` over 443 (NAT gateway or a VPC endpoint).

### Additionally for greenfield mode

- **AWS credentials** with permission to create EKS clusters, IAM roles + policy attachments, EKS managed node groups, and security-group rules.
- **At least 2 private subnets in different AZs** in the RDS's VPC, with NAT egress so the control plane and worker nodes can reach Datadog and ECR. Pass them via `private_subnet_ids`.
- **Awareness of the ongoing cost** — see [Cost](#cost).

## Manual SQL

Identical to the Fargate example — run this once against the RDS instance using a role with `rds_superuser` (the RDS master). Repeat the schema/grants block **in every database** you want monitored.

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
# Edit terraform.tfvars — pick BYO or greenfield (see the file header) and fill
# in the rest (rds_security_group_id, rds_endpoint, database_name,
# datadog_user_password, datadog_api_key, …).

terraform init
terraform plan
terraform apply
```

What gets created depends on the mode:

- **BYO mode** (`eks_cluster_name` set) — ~3 resources visible in Terraform: a `kubernetes_namespace`, a `helm_release` (which deploys the node Agent DaemonSet, Cluster Agent, and Cluster Check Runner inside your cluster), and a single `aws_security_group_rule` on the RDS SG. Apply takes ~3 minutes.
- **Greenfield mode** (`eks_cluster_name = ""`) — ~13 resources: the BYO 3 plus an `aws_eks_cluster`, `aws_eks_node_group`, two `aws_iam_role`s for the cluster and node, and five `aws_iam_role_policy_attachment`s. Apply takes ~15-20 minutes (most of it waiting for the EKS control plane to come up).

## Verify

1. Helm release is healthy:
   ```bash
   helm status -n $(terraform output -raw namespace) $(terraform output -raw helm_release_name)
   kubectl -n $(terraform output -raw namespace) get pods
   ```
2. The cluster check is dispatched. From the Cluster Agent:
   ```bash
   kubectl -n $(terraform output -raw namespace) exec -it \
     deploy/$(terraform output -raw cluster_agent_deployment) -- \
     agent clusterchecks
   ```
   Look for a `postgres` entry assigned to one of the cluster-check runner pods.
3. Tail the runner logs and look for the `[postgres]` check running cleanly:
   ```bash
   kubectl -n $(terraform output -raw namespace) logs -l app=$(terraform output -raw cluster_check_runner_deployment) -f
   ```
   You should see lines like `Running check postgres` and no `dbm` or `pg_stat_statements` errors.
4. In the Datadog UI:
   - **Infrastructure → Kubernetes**: the EKS cluster appears with node and pod metrics.
   - **Databases → List**: the RDS host appears with DBM enabled.
   - **Databases → Query Metrics**: rows render within ~2 minutes of database traffic.

## Teardown

```bash
terraform destroy
```

What gets removed depends on the mode:

- **BYO mode** — removes the helm release, the namespace, and the ingress rule we added to the RDS SG. **The EKS cluster, the worker nodes, the RDS instance, and the Postgres `datadog` user are untouched.** This is the BYO assertion: dropping our Terraform onto your existing cluster will not nuke it on destroy.
- **Greenfield mode** — removes everything: helm release, namespace, RDS SG ingress rule, EKS node group, EKS cluster, and the IAM roles + policy attachments this template created. **The RDS instance and the Postgres `datadog` user are still untouched.** Stops the ~$0.10/hr control-plane charge once destroy completes (typically ~10 minutes).

## Security note

Both `datadog_user_password` and `datadog_api_key` are passed straight into the helm release values, but they land in different Kubernetes objects:

- **`datadog_api_key`** — rendered into a Kubernetes **Secret** by the chart. Readable by anyone with `get secret` in the release namespace.
- **`datadog_user_password`** — embedded in the Postgres check yaml under `clusterAgent.confd` and rendered into a Kubernetes **ConfigMap**. Readable by anyone with `get configmap` in the release namespace.

This is fine for a demo; for production:

1. Store both in **AWS Secrets Manager** (or another secret store).
2. Use the External Secrets Operator (or the chart's `apiKeyExistingSecret` / `secretBackend` settings) to project them into the agent at runtime.
3. Reference the password in the Postgres check via `password = "ENC[...]"` with a configured secret backend, or via `${ENV_VAR}` after wiring the env var into the cluster-check runner pod spec.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Cluster-check runner logs show `connection refused` to RDS | RDS SG ingress rule didn't apply, or runner pods are on nodes whose SG is not `eks_node_security_group_id` |
| Runner logs show `pg_stat_statements is not loaded` | RDS parameter group missing `shared_preload_libraries=pg_stat_statements`, or RDS not rebooted |
| Runner logs show `permission denied for relation pg_stat_activity` | `pg_monitor` role not granted to `datadog` user |
| `agent clusterchecks` on the Cluster Agent shows the postgres check as unscheduled | `clusterChecksRunner.enabled` was disabled, or the runner deployment has zero ready pods |
| No data in Datadog UI | API key wrong, `DD_SITE` mismatched, or pods can't reach `*.${DD_SITE}` (NAT egress / VPC endpoint missing) |
| `query_samples` empty | `datadog.explain_statement` function not created in the monitored database |
| `terraform plan` fails reading the EKS cluster | IAM principal running Terraform lacks `eks:DescribeCluster` / `eks:GetToken`, or is not mapped in `aws-auth` / EKS access entries for the cluster |

## Files

- `versions.tf` — Terraform + provider pins, EKS-backed `helm`/`kubernetes` provider config
- `variables.tf` — inputs (secrets marked `sensitive`)
- `main.tf` — namespace, helm release (Agent + Cluster Agent + CLC runners + Postgres cluster check), RDS-side ingress rule
- `outputs.tf` — useful identifiers for verification
- `terraform.tfvars.example` — fill-in-the-blanks template
