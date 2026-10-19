# Mono Senior DevOps Engineer Assessment

Simple TypeScript Node.js API exposing health, metrics and account endpoints.

## Assessment Requirments

You have been provided with a simple web service that serves 4 endpoints, you are required to do the following;

1. Add a DOCKERFILE in the repository to serve the service in containerized infra
2. Provision an EKS cluster on AWS with terraform (you can create a free tier account on AWS)
3. Create a docker image and upload on AWS Elastic container registry using the same Terraform file
4. Deploy the docker image from AWS ECR to the kubernetes cluster
5. Write a CI/CD script for GitHub actions that uses your Terraform file to;

   i. create or updates the docker image and deploy to AWS Elastic container registry 
     ii. deploy the docker images to kubernetes cluster; anytime that there is a push on the default branch (you can make changes to the code to confirm this works)
6. Consider the app is accessible via the public internet, while accounting for security and availability in your architecture (feel free to use other AWS services that to strengthen your solution)

## Bonus Requirements

1. collect `/metrics` with Prometheus (or Grafana Alloy)
2. A plan for upgrading the EKS cluster version with no downtime
3. extend the metric collected and build a reasonable a Grafana dashboard for request rate, error rate and latency, and commit it as JSON

## Submission

1. Add a `SOLUTION.md`  or a link to a document covering:
   - **Architecture**: a diagram and a short description
   - **How to run it**: deploy from scratch, and tear down
   - **Decisions and trade-offs**: what you chose, what you rejected, and why
   - **Security and compliance**: how your setup handles least-privilege IAM, secrets, encryption in transit and at rest, and audit logging, and which ISO 27001 / PCI DSS controls it would provide evidence for  (brief is fine and your actual implemention may not cover all but your solution to speak to every technical expectation of your solution)
   - **Backup and recovery**: your suggested RTO/RPO for this service and how you would meet them
   - **Gaps**: what is missing before this is truly production-ready and how you intend to handle this
2.  Share a GitHub repo with your solution
   - Include the updated service
   - Terraform, 
   - Kubernetes manifests/chart
   - workflows
   - dashboard JSON and `SOLUTION.md` or documentation of your solution
3. A live URL is optional
4. Share how you used AI for your solution (if you did)

## How to Run the Application

```bash
npm install
npm run build
npm start        # serves on PORT (default 3000)
```

Development (watch mode):

```bash
npm run dev
```

## Project structure

```text
src/
├── app.ts                 # App bootstrap: TypeDI container wiring + controller/middleware registration
├── server.ts              # Entry point: starts the HTTP listener
├── controllers/           # routing-controllers JSON controllers
│   ├── account.controller.ts
│   ├── health.controller.ts
│   └── metrics.controller.ts
├── services/              # Business logic, injected into controllers/middleware via TypeDI
│   ├── account.service.ts
│   └── metrics.service.ts
├── middleware/            # routing-controllers Express middlewares
│   ├── error-handler.middleware.ts    # Maps thrown HttpErrors to { error: ... } responses
│   ├── not-found.middleware.ts        # 404 fallback / 405 for non-GET methods
│   └── request-metrics.middleware.ts  # Counts every request into http_requests_total
└── interfaces/
    └── account.ts
```

## Endpoints

| Endpoint               | Description                                              |
| --------------------- | -------------------------------------------------------- |
| `GET /health`         | Liveness check with uptime                               |
| `GET /metrics`        | Prometheus metrics via prom-client                       |
| `GET /getAccount`     | All accounts from the dummy array                        |
| `GET /getAccount?id=1` | Single account by id (404 if not found)                |

Non-GET methods are rejected with `405`, unknown routes with `404`.

## Metrics

Exposed in Prometheus text format at `GET /metrics`:

- Default Node.js process metrics (CPU, memory, event loop, GC, ...)
- `http_requests_total{method,route,status_code}` — custom request counter
