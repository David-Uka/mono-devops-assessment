# How AI was used in this submission

I used Claude (Anthropic's Claude Code CLI) as a pair-programmer throughout,
with me directing the architecture and reviewing every file before it was
committed.

**What the AI did**

* Drafted the first version of most files from my specification: the
  multi-stage Dockerfile, the Helm chart, the three Terraform stacks, the GitHub
  Actions workflows and the Grafana dashboard JSON.
* Looked up current versions (EKS 1.36/1.37, module and provider majors, chart
  versions) so pins are real rather than remembered.
* Ran the local verification loop: typecheck, `helm lint` / `helm template`,
  `terraform validate`, container smoke tests including the SIGTERM drain test.
* Wrote the first draft of the documentation, which I then edited.

**What I did**

* Chose the architecture: ALB + WAF in front of private nodes, Terraform split
  into bootstrap / infra / platform, OIDC rather than long-lived keys, blocking
  `/metrics` at the edge rather than in the app.
* Reviewed and corrected the generated code. Examples: the first chart draft
  lost `.Values` scope inside a `range` and failed to render; the first
  bootstrap stack declared `required_providers` twice; the ALB controller chart
  had moved to a 3.x major since the model's training data, so the pin was
  wrong; the Kubernetes 3.x provider wants `exec` as a block, not an
  attribute; `fileset()` returns a set and needed `tolist()` before `concat()`.
* Made the cost and security trade-off calls documented in `SOLUTION.md`
  (single NAT gateway, on-demand `t3.medium`, Grafana not exposed).
* Deployed it, debugged what broke against the real AWS account, and wrote up
  the gaps honestly.

**What I did not do**

* I did not paste the brief into a model and submit the output. Every design
  decision in `SOLUTION.md` is one I can defend in an interview, and the gaps
  section lists what I know is still missing.
