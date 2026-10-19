# Solution: Mono DevOps assessment

A public, internet-facing deployment of the assessment API on EKS, provisioned
end to end with Terraform and rolled out from GitHub Actions on every push to
`main`. Everything required by the brief is here; the bonus items are covered
too, and the last section is honest about what is still missing.

| Requirement | Where |
|---|---|
| 1. Dockerfile | `Dockerfile` (multi-stage, non-root, read-only rootfs friendly) |
| 2. EKS with Terraform | `terraform/infra` |
| 3. Image built and pushed to ECR by Terraform | `terraform/platform/image.tf` |
| 4. Deploy from ECR to the cluster | `terraform/platform/app.tf` + `charts/api` |
| 5. CI/CD on push to default branch | `.github/workflows/deploy.yml` |
| 6. Public, secure, available | ALB + WAF, private nodes, HPA/PDB, multi-AZ (below) |
| Bonus 1. Prometheus scrapes `/metrics` | `terraform/platform/monitoring.tf`, `ServiceMonitor` in the chart |
| Bonus 2. Zero-downtime upgrade plan | `docs/eks-upgrade-plan.md` |
| Bonus 3. Extended metrics + Grafana dashboard | `src/services/metrics.service.ts`, `dashboards/api-red.json` |
| Bonus 4. Live URL | printed by `terraform output api_url` (see "Live URL") |
| AI usage | `docs/ai-usage.md` |

## Architecture

```
                         Internet
                            │
                   ┌────────▼────────┐
                   │   AWS WAF v2    │  managed rules + per-IP rate limit
                   └────────┬────────┘
                            │
                   ┌────────▼────────┐   public subnets, 2 AZs
                   │  ALB (HTTPS)    │   access logs -> S3
                   │  /metrics -> 403│   fixed-response rule at the edge
                   └────────┬────────┘
   ┌────────────────────────┼─────────────────────────────┐  VPC 10.40.0.0/16
   │  private subnets, 2 AZs│  (no public IPs on nodes)   │
   │   ┌────────────────────▼───────────────────────┐     │
   │   │ EKS 1.36  (managed node group, t3.medium)  │     │
   │   │                                            │     │
   │   │  ns api (PSA: restricted)                  │     │
   │   │   Deployment api  x2..6 (HPA)  ◄── PDB     │     │
   │   │   NetworkPolicy, non-root, ro-rootfs       │     │
   │   │                                            │     │
   │   │  ns monitoring                             │     │
   │   │   Prometheus ──scrape /metrics──► api pods │     │
   │   │   Grafana (ClusterIP, RED dashboard)       │     │
   │   │                                            │     │
   │   │  kube-system: ALB controller (IRSA),       │     │
   │   │   coredns, vpc-cni, metrics-server         │     │
   │   └────────────────────────────────────────────┘     │
   │          │ NAT GW (egress only)      VPC flow logs ──► CloudWatch
   └──────────┼──────────────────────────────────────────┘
              ▼
     ECR (KMS, immutable tags, scan on push)   CloudWatch (control-plane audit logs)

   GitHub Actions ──OIDC──► IAM role (no static keys) ──► terraform apply
```

**Request path.** Client → WAF → ALB (TLS terminates here when a domain is
configured) → pod IP target group (ALB `target-type: ip`, so no NodePort hop)
→ Express on :3000. `/metrics` never reaches a pod from the internet: the ALB
answers it with a fixed 403.

**Delivery path.** Push to `main` → `deploy.yml` assumes the deploy role via
OIDC → `terraform apply` in `infra` (idempotent; a no-op after the first run)
→ `terraform apply` in `platform`, which builds the image on the runner,
pushes it to ECR tagged with the git sha, and upgrades the Helm release →
smoke test against the live URL asserting `/health` is 200 and `/metrics` is 403
→ verify the Deployment is running the pushed sha.

### Terraform layout

```
terraform/
├── bootstrap/   once, by a human: state bucket (versioned, KMS), GitHub OIDC provider,
│                two IAM roles (plan: read-only; deploy: scoped)
├── infra/       VPC + flow logs, KMS CMK, EKS (private nodes, audit logs, secrets
│                encryption, IMDSv2), ECR, ALB-controller IRSA role, WAF, ALB log bucket,
│                optional ACM cert
└── platform/    docker build + ECR push, ALB controller, kube-prometheus-stack,
                 dashboard ConfigMap, the api Helm release (ingress, WAF association)
```

## How to run it

Prerequisites: AWS credentials in the shell, `terraform >= 1.10`, `docker`,
`helm`, `kubectl`, `gh` (optional, for the Makefile to discover the repo).

### One-time bootstrap (local, ~2 min)

```bash
export AWS_PROFILE=<profile> AWS_REGION=us-east-1
make bootstrap GITHUB_REPO=<owner>/<repo>
# note the three outputs
```

Then in the GitHub repo set **variables** `AWS_DEPLOY_ROLE_ARN`,
`AWS_PLAN_ROLE_ARN`, `TF_STATE_BUCKET` (from the outputs) and optionally
`API_DOMAIN_NAME`, `ROUTE53_ZONE_ID`; and the **secret**
`GRAFANA_ADMIN_PASSWORD`. Create a `prod` environment (optionally with a
required reviewer, which turns `deploy.yml` into a one-click approval gate).

### Deploy from scratch

Either push to `main` and let `deploy.yml` do it, or locally:

```bash
make deploy          # infra (~15 min for EKS) then platform (~8 min)
make kubeconfig
terraform -chdir=terraform/platform output api_url
```

### Verify

```bash
URL=$(terraform -chdir=terraform/platform output -raw api_url)
curl $URL/health
curl "$URL/getAccount?id=66ab443c4d4ac0b1cdf456911"
curl -i $URL/metrics          # 403 from the ALB
make grafana                  # http://localhost:3001, dashboard "Mono API - RED"
```

### Tear down

```bash
make destroy         # platform first (releases the ALB), then infra
# or: Actions -> Destroy -> type mono-api-prod
```

Bootstrap resources (state bucket, OIDC roles) are left in place deliberately;
`terraform -chdir=terraform/bootstrap destroy` removes them.

### Local development

```bash
npm ci && npm run dev                 # watch mode on :3000
make build && make run                # the production image
```

## Decisions and trade-offs

**Three Terraform stacks, not one.** The brief says "the same Terraform file".
I split it because the Kubernetes and Helm providers need a live API endpoint
at plan time; putting cluster creation and Helm releases in one root module
works on the first apply and then bites you on every destroy and on any plan
where the cluster is being replaced. The `deploy.yml` workflow still runs the
whole chain on every push, so from the outside it behaves as one pipeline.
Rejected: a single root module with `-target` gymnastics.

**Image built by Terraform (`kreuzwerker/docker`) rather than `docker/build-push-action`.**
Requirement 3 asks for Terraform to do it, and it has a real upside: the image,
its tag and the Helm release are in one state, so a plan shows exactly which
image a rollout will ship. Downside: the build runs wherever `terraform apply`
runs, so the runner needs Docker (GitHub's do) and the image is rebuilt on
tag change even if the layers are cached. Rejected: `null_resource` +
`local-exec` (no diffing, no drift detection).

**Helm chart rather than raw manifests.** One chart, values injected by
Terraform, so there is exactly one definition of the workload. The chart is
deliberately strict: `image.repository`/`tag` are `required`, so nothing can
deploy `latest` by accident.

**ALB + WAF rather than NLB or an in-cluster ingress.** The ALB terminates
TLS, speaks HTTP/2, gives per-path rules (used for the `/metrics` block),
integrates with WAF natively and writes access logs. ingress-nginx would add a
hop and a component to patch. Rejected: API Gateway (overkill for four GET
endpoints, and cost per request). Rejected: CloudFront in front of the ALB
(good for caching and edge TLS but adds nothing for an uncacheable API with
one region; listed in gaps as the next step if the audience is global).

**Managed node group, on-demand `t3.medium` x2 across 2 AZs.** Two nodes is
the minimum that lets a PDB of `minAvailable: 1` and a drain coexist.
`t3.medium` because smaller types hit the ENI pod limit once the ALB
controller and Prometheus are on the cluster. Rejected: Fargate (no
DaemonSets, slower scale-out, no node-exporter). Rejected for now: Karpenter
(right answer at scale; a second component to run for a two-node cluster).

**Single NAT gateway.** Cuts ~$32/month. The failure mode is loss of egress in
one AZ if the NAT's AZ fails, and this app has no outbound dependencies at all
(its only egress is ECR pulls at pod start and DNS). Flip
`single_nat_gateway = false` for per-AZ NAT when that changes.

**EKS API endpoint public but allow-listed.** `endpoint_public_access_cidrs`
defaults to open so the assessment is reproducible; in a real account it is
the office/VPN CIDR plus the CI runner egress, or private-only with a bastion.

**`/metrics` blocked at the edge, not in the app.** Keeping the app's
behaviour identical in every environment is worth more than an `if (!internal)`
branch, and the ALB fixed-response rule is declarative and visible in the plan.
Prometheus scrapes the pod directly inside the VPC and never crosses the ALB.

**Authentication mode `API` with access entries**, not the legacy
`aws-auth` ConfigMap, so cluster access is IAM-auditable.

**kube-prometheus-stack rather than Grafana Alloy + Amazon Managed Prometheus.**
One Helm release gives Prometheus, Grafana, the operator and the
`ServiceMonitor` CRD; the dashboard is loaded from git via the sidecar so it is
reviewable in a PR. Alertmanager is disabled to keep the footprint small on two
nodes. AMP/AMG is the right move for retention and HA and is in the gaps.

**OIDC, not access keys, for CI.** Two roles: `plan` (ReadOnly + state) can be
assumed from pull requests; `deploy` only from `refs/heads/main`. The deploy
role is PowerUser plus an IAM grant restricted to resources prefixed
`mono-api-*`, so Terraform can create the cluster/node/IRSA roles and nothing
else in the account.

### Code changes to the service

Kept minimal and all in service of running well on Kubernetes:

* `src/server.ts`: SIGTERM/SIGINT handler that stops accepting connections,
  drains in-flight requests and exits (verified: `docker stop` returns in <1s,
  not after the 10s kill timeout). Keep-alive timeout raised above the ALB
  idle timeout to avoid 502s on connection reuse.
* `src/services/metrics.service.ts`: added `http_request_duration_seconds`
  histogram and `http_requests_in_flight` gauge; the `route` label is now
  normalised so unknown paths collapse to `unmatched` instead of creating one
  series per scanner request (the original would have let anyone blow up
  Prometheus cardinality by walking random URLs).
* `src/middleware/request-metrics.middleware.ts`: times each request with
  `process.hrtime.bigint()`.

Observed, not changed: all three dummy accounts share the same `id`, so
`/getAccount?id=` can only ever return the first one. That is business data,
not infrastructure, so I left it and am flagging it.

## Security and compliance

| Concern | Implementation |
|---|---|
| **Least-privilege IAM** | No long-lived keys anywhere. GitHub → AWS via OIDC with branch-scoped trust. Deploy role's IAM rights are limited to `mono-api-*` resources and `PassRole` only to EKS/EC2/Pod Identity. ALB controller uses IRSA with the vendor policy only. Pods run with `automountServiceAccountToken: false`. Nodes use IMDSv2 with hop limit 1 so a pod cannot reach the node's instance role. |
| **Secrets** | Kubernetes Secrets are envelope-encrypted with a customer-managed KMS key (rotation on). The app has no secrets today; when it does, the path is External Secrets Operator + Secrets Manager via IRSA, never values in `values.yaml`. Grafana admin password is a GitHub secret passed as a sensitive Terraform variable. |
| **Encryption in transit** | TLS 1.2/1.3 at the ALB (`ELBSecurityPolicy-TLS13-1-2-2021-06`) with HTTP→HTTPS redirect when a domain is set. ALB→pod is plain HTTP inside the VPC on private subnets; a service mesh (mTLS) is in the gaps. State bucket enforces TLS-only access. |
| **Encryption at rest** | KMS CMK for EKS secrets, ECR images and node EBS root volumes. S3 state bucket SSE-KMS; ALB logs SSE-S3 (the only mode ALB delivery supports). |
| **Network** | Nodes in private subnets, no public IPs. Node SG only accepts the app port from inside the VPC. `NetworkPolicy` restricts pod ingress to the app port and egress to DNS. Namespace enforces Pod Security Admission `restricted`. |
| **Edge protection** | WAF: AWS Common, Known Bad Inputs, IP Reputation managed rule groups, plus a 2000 req/5 min per-IP rate limit. ALB drops invalid headers. Only GET is implemented; everything else is 405. |
| **Supply chain** | Immutable ECR tags, scan-on-push, image tag = git sha, Trivy gate in CI (fails on fixable HIGH/CRITICAL), `npm ci` from the lockfile, pinned action/provider/module versions. |
| **Audit logging** | EKS control-plane logs (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) to CloudWatch, 30-day retention. VPC flow logs. ALB access logs to S3 with 90-day lifecycle. WAF sampled requests + CloudWatch metrics. Terraform state is versioned, so every infrastructure change has a before/after. |
| **Runtime hardening** | Non-root UID 1000, `readOnlyRootFilesystem`, all capabilities dropped, `seccompProfile: RuntimeDefault`, no privilege escalation, memory limits. |

### Control mapping (evidence this setup would produce)

| Control | ISO 27001:2022 | PCI DSS v4.0 | Evidence from this solution |
|---|---|---|---|
| Access control / least privilege | A.5.15, A.5.18, A.8.2 | 7.2, 7.3, 8.3 | OIDC trust policies, scoped deploy role, access entries, IRSA |
| Cryptography | A.8.24 | 3.5, 4.2 | KMS CMK with rotation, TLS policy on ALB, encrypted EBS/ECR/S3 |
| Network security | A.8.20, A.8.21, A.8.22 | 1.2, 1.3, 1.4 | Private subnets, SGs, NetworkPolicy, WAF |
| Logging and monitoring | A.8.15, A.8.16 | 10.2, 10.3, 10.4 | EKS audit logs, flow logs, ALB logs, Prometheus/Grafana |
| Secure configuration | A.8.9 | 2.2 | Everything in Terraform/Helm, CI validates `fmt`/`validate`/`lint` |
| Vulnerability management | A.8.8 | 6.3, 11.3 | ECR scan-on-push, Trivy in CI |
| Change management | A.8.32 | 6.5 | PR plan comments, branch-gated deploy role, `prod` environment approvals |
| Secure development | A.8.25, A.8.28 | 6.2 | Lockfile, typecheck, non-root image, no secrets in repo |
| Backup / continuity | A.8.13, A.8.14 | 12.10 | Versioned state, ECR retention, HA across AZs (see below) |

**Not covered here but needed for a real PCI scope**: this API returns account
numbers and balances, so in production it would be in-scope CDE-adjacent data.
That means authentication on the endpoints (there is none; it is a public
read-only API by the brief's design), field-level logging controls so account
numbers never land in ALB logs via query strings, quarterly ASV scans, and a
documented key-management procedure for the CMK.

## Backup and recovery

**What there is to back up.** The service is stateless: the "database" is an
in-memory array. The things that matter are the infrastructure definition
(git), the Terraform state (versioned S3), the images (ECR, 20 tags retained)
and the cluster configuration (Helm releases, reproducible from Terraform).

**Suggested targets for this service**

| Scenario | RTO | RPO | How it is met |
|---|---|---|---|
| Pod / node failure | seconds | 0 | ≥2 replicas, HPA, PDB, topology spread across AZs; ALB health checks pull a bad target in 15–30 s |
| AZ failure | < 1 min | 0 | Nodes and ALB in 2 AZs; the HPA back-fills capacity. Single NAT is the known weak point (egress only) |
| Bad deploy | < 5 min | 0 | `maxUnavailable: 0` means a failing image never replaces a healthy pod; `terraform apply -var image_tag=<previous sha>` rolls back |
| Cluster loss / region-wide incident | ~30 min | 0 (stateless) | `make deploy` into a fresh account or region from git + state; ECR images are the only artefact and can be replicated cross-region with one resource |
| Terraform state corruption | < 10 min | last apply | S3 versioning; restore the previous object version |

**If the app grew real state** (say the accounts moved to RDS): Multi-AZ RDS
with automated backups and PITR gives RPO ≈ 5 min / RTO ≈ 10 min for an
instance failure; cross-region read replica for regional DR; Velero with EBS
snapshots for anything persisted in-cluster. I would also add a scheduled
`terraform plan` drift check so backups are not silently out of date relative
to what is deployed.

## Gaps: what is missing before this is truly production-ready

Ordered by what I would do first.

1. **Authentication/authorization on the API.** The brief specifies a public
   read-only API, but `/getAccount` returns account numbers. Real production
   needs OAuth2/JWT at the ALB (Cognito or OIDC action) or in the app, and
   a WAF rule that rejects requests without an `Authorization` header.
2. **A real domain and TLS.** The code paths exist (`domain_name` +
   `route53_zone_id` → ACM → HTTPS listener with redirect); without a domain
   the live URL is plain HTTP on the ALB hostname. Add HSTS once on HTTPS.
3. **Separate staging environment.** Same modules, a second `tfvars` and state
   key, and the `prod` deploy job gated on a staging smoke test.
4. **Alerting.** Prometheus rules for error rate > 1%, p95 > 500 ms, pods
   unavailable; Alertmanager → PagerDuty/Slack. Currently the dashboard shows
   the problem but nobody is paged.
5. **Managed, durable observability.** Prometheus here has 7-day retention on
   an EBS volume; move to Amazon Managed Prometheus + Grafana (or Grafana
   Cloud) and ship logs (Fluent Bit → CloudWatch/OpenSearch). Add
   OpenTelemetry tracing when there is more than one service.
6. **Cluster autoscaling.** The HPA scales pods, nothing scales nodes. Karpenter
   with a `NodePool` and `expireAfter` for continuous rotation.
7. **mTLS / service mesh** once there is east-west traffic worth encrypting.
8. **Policy as code.** Kyverno or OPA Gatekeeper to enforce the PSA/label/image
   registry rules in-cluster rather than by convention; `tflint`/`checkov`
   in CI for the Terraform.
9. **Per-AZ NAT**, deletion protection on the ALB, `force_delete = false` on
   ECR, `prevent_destroy` on the state bucket: all turned off here so the
   assessment can be torn down cleanly. Flip them for prod.
10. **Cost controls.** Budgets + alerts, Spot for non-critical capacity, and a
    nightly scale-to-zero for non-prod.
11. **Provider lock files.** `.terraform.lock.hcl` is git-ignored here because
    the hashes were generated on macOS/arm64 and CI runs on Linux. The fix is
    `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`
    and committing the result, so CI and laptops resolve identical binaries.
12. **Runbooks and on-call.** The upgrade runbook exists; incident, rollback
    and key-rotation runbooks do not yet.

## Live URL

The URL is an output of the platform stack and printed by the deploy workflow.
It is included in the submission email when the environment is up; the
environment is torn down between sessions to keep cost near zero, and
`make deploy` recreates it in about 25 minutes.
