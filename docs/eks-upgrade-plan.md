# EKS upgrade plan: zero-downtime 1.36 -> 1.37

This is the runbook for moving the `mono-api-prod` cluster one minor version
forward without dropping a request. The same steps apply to any N -> N+1 move;
EKS does not allow skipping minors on the control plane.

## What makes a drain safe

The chart carries the protections; the procedure below sequences them.

| Mechanism | Where | Effect during a node drain |
|---|---|---|
| 2+ replicas spread across AZs and hosts | `topologySpreadConstraints`, HPA `minReplicas: 2` | one node going away never takes every pod |
| `PodDisruptionBudget minAvailable: 1` | `charts/api/templates/pdb.yaml` | the drain waits instead of evicting the last pod |
| `maxUnavailable: 0, maxSurge: 1` rolling update | deployment strategy | new pods are ready before old ones stop |
| readiness probe + ALB `target-type: ip` | chart + ingress annotations | ALB only routes to ready pods; deregistration delay drains in-flight requests |
| `preStop: sleep 5` + SIGTERM handler | deployment + `src/server.ts` | the pod finishes in-flight requests after it is removed from the target group |

With those in place a drain is a slow rolling restart.

## Pre-flight (day before)

1. Read the release notes for 1.37 and run Pluto against the cluster and the
   chart to catch removed APIs:
   ```bash
   pluto detect-helm --target-versions k8s=v1.37.0
   kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
   aws eks list-insights --cluster-name mono-api-prod   # EKS upgrade insights
   ```
2. Check add-on compatibility for the target version and review what
   `most_recent = true` in `terraform/infra/eks.tf` will resolve to:
   ```bash
   for a in vpc-cni coredns kube-proxy eks-pod-identity-agent metrics-server; do
     aws eks describe-addon-versions --kubernetes-version 1.37 --addon-name $a \
       --query 'addons[0].addonVersions[0].addonVersion' --output text
   done
   ```
3. Check the ALB controller and kube-prometheus-stack support matrices for 1.37
   and bump `alb_controller_chart_version` / `kube_prometheus_stack_version` first
   if required (they roll independently of the cluster).
4. Confirm every PDB is satisfiable: `kubectl get pdb -A` must show
   `ALLOWED DISRUPTIONS >= 1`. A budget at 0 blocks the drain forever. I hit
   this last month on a single-node cluster, where coredns's own PDB kept a
   node group stuck in DELETING until I deleted the budget.
5. Capacity headroom: node group `max_size` must be at least
   `desired_size + 1` so a surge node can be added during the rollout.
6. Take a Velero backup of the `api` and `monitoring` namespaces (see
   SOLUTION.md, Backup and recovery) and note the Terraform state object version.

## Execution (change window ~45 min, no user impact expected)

### Step 1: control plane (~10 min, zero data-plane impact)

```hcl
# terraform/infra/variables.tf
variable "kubernetes_version" { default = "1.37" }
```

```bash
cd terraform/infra && terraform plan   # expect: eks cluster version in-place update only
terraform apply
```

The managed control plane upgrades in place with rolling API servers. Existing
connections to the API endpoint are briefly reset; workloads do not notice.

### Step 2: managed add-ons (~5 min)

The `addons` map uses `most_recent = true`, so the same apply moves vpc-cni,
coredns, kube-proxy, pod-identity-agent and metrics-server to the
1.37-compatible builds. coredns has 2 replicas and its own PDB, so DNS stays up.

### Step 3: node group (~20 min, this is where the drain happens)

The managed node group picks up the new AMI once the cluster version changes.
The apply triggers a rolling update governed by
`update_config.max_unavailable_percentage = 33`:

1. EKS launches a surge node on the new AMI and waits for it to be Ready.
2. It cordons one old node and evicts pods, honouring the PDB.
3. The scheduler places the evicted `api` pod on a new node; the readiness
   probe gates it in; the ALB target group registers the new pod IP.
4. The old pod receives SIGTERM, sleeps 5s (the ALB has deregistered it),
   finishes in-flight requests, exits.
5. Repeat for the next node.

Watch it:

```bash
kubectl get nodes -w                                  # old nodes drain, new ones join
kubectl -n api get pods -o wide -w                     # pods move, never fewer than 1 ready
watch 'curl -s -o /dev/null -w "%{http_code}\n" https://<api>/health'
```

The Grafana RED dashboard should show a flat request rate and no 5xx for the
whole window. If errors spike, interrupt the apply; EKS finishes the node it
is on and stops.

### Step 4: verify

```bash
kubectl version                     # server 1.37
kubectl get nodes                   # all on the new AMI / kubelet 1.37
kubectl -n api rollout status deploy/api
kubectl get pdb -A                  # disruptions allowed again
```

## Rollback

* Control plane: EKS cannot downgrade. Rollback means fixing forward, which
  is why the deprecated-API scan in pre-flight is mandatory.
* Node group: if the new AMI misbehaves, pin `ami_release_version` in the
  node group to the previous release and apply. EKS rolls the nodes back the
  same way it rolled them forward, PDB-safe.
* Add-ons: pin the previous `addon_version` for the misbehaving add-on and apply.
* App: unaffected by the cluster version; the last known-good image tag is
  in ECR and `terraform apply -var image_tag=<sha>` redeploys it.

## Next steps

* Run the whole thing against a `staging` cluster first with the same Terraform
  (one more `tfvars` file).
* Blue/green node groups instead of in-place: create `general-137`, cordon and
  drain `general` by hand with `kubectl drain --ignore-daemonsets
  --delete-emptydir-data`, then delete the old group. Slower but reversible at
  every step.
* Karpenter with `expireAfter` so node rotation is continuous, not an event.
