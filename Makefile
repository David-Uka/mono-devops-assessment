# Local driver for the same steps CI runs. Requires AWS creds in the shell
# (e.g. `export AWS_PROFILE=David`), docker, terraform >= 1.10, helm, kubectl.
SHELL := /bin/bash
REGION ?= us-east-1
STATE_BUCKET ?= $(shell cd terraform/bootstrap 2>/dev/null && terraform output -raw state_bucket 2>/dev/null)
IMAGE_TAG ?= $(shell git rev-parse --short=12 HEAD)-local-$(shell date +%s)
GITHUB_REPO ?= $(shell gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
GITHUB_IDS  ?= $(shell gh api repos/$(GITHUB_REPO) --jq '"-var github_owner_id=\(.owner.id) -var github_repo_id=\(.id)"' 2>/dev/null)

.PHONY: help build run test bootstrap infra platform deploy destroy kubeconfig grafana

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n",$$1,$$2}'

build: ## build the image locally
	docker build -t mono-api:$(IMAGE_TAG) .

run: build ## run the image locally on :3000
	docker run --rm -p 3000:3000 mono-api:$(IMAGE_TAG)

test: ## typecheck, helm lint, terraform validate
	npm run typecheck
	helm lint charts/api --set image.repository=x --set image.tag=y
	for s in bootstrap infra platform; do (cd terraform/$$s && terraform init -backend=false -input=false >/dev/null && terraform validate); done

bootstrap: ## one-time: state bucket + GitHub OIDC roles (local state)
	cd terraform/bootstrap && terraform init -input=false && terraform apply -var "github_repo=$(GITHUB_REPO)" $(GITHUB_IDS)

infra: ## VPC, EKS, ECR, WAF
	cd terraform/infra && terraform init -input=false -backend-config="bucket=$(STATE_BUCKET)" && terraform apply

platform: ## build+push image, ALB controller, monitoring, app
	cd terraform/platform && terraform init -input=false -backend-config="bucket=$(STATE_BUCKET)" && terraform apply -var "image_tag=$(IMAGE_TAG)"

deploy: infra platform ## everything from scratch

destroy: ## tear down (platform first so the ALB is released before the VPC)
	-cd terraform/platform && terraform destroy -var "image_tag=$(IMAGE_TAG)"
	cd terraform/infra && terraform destroy

kubeconfig: ## point kubectl at the cluster
	aws eks update-kubeconfig --region $(REGION) --name mono-api-prod

grafana: ## port-forward Grafana to localhost:3001 and print the admin password
	@echo "admin password: $$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80
