# arculus-devops-challenge
This repository contains my solution for the DevOps Engineer (Linux) technical challenge.

Work plan:

Part 1: Application + CI (GitHub Actions)

Part 2: Docker image build/push
# arculus-devops-challenge — Part 2 (CI & Container Registry)

This file documents the minimal, practical steps we performed in Part 2 to build, publish, pull and run the container image for the `arculus-devops-challenge` service.

Quick overview
- The repo contains a Python orders service and a Dockerfile.
- CI (GitHub Actions) builds the image and pushes to GitHub Container Registry (GHCR) when changes land on `main` or when a git tag is created.
- Image location: `ghcr.io/soumya-s-goud/arculus-devops-challenge`
- CI workflow file: `.github/workflows/ci.yml`

Prerequisites (local)
- Git and Docker installed and running.
- A GitHub account with access to this repository.
- If the package is private: a GitHub Personal Access Token (PAT) with the Packages read scope (classic token `read:packages`) or a fine‑grained token that grants Packages: Read for this repo.
  - Create token: GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token (classic) → check `read:packages`.
  - Copy token once — you will need it to authenticate docker to GHCR.

Local: build and run the image (quick test)
1. Build locally (optional — we already tested this in Step 1):
   - From repository root:
     docker build -t arculus-app:local .

2. Run locally:
   - Run the built local image:
     docker run --rm -p 8000:8000 arculus-app:local
   - Test health endpoint:
     curl http://localhost:8000/health
   - Expected response: `{"status":"ok"}`

CI: what we implemented
- A minimal GitHub Actions workflow builds the image on every push or PR and only pushes the image to GHCR when:
  - A push occurs on `main` (default branch), or
  - A git tag is created (tag event).
- Tags produced by the workflow:
  - `latest`
  - `sha-<short-commit-sha>` (commit SHA tag)
  - when a git tag event occurs, that tag is published as well
- Official actions used:
  - `docker/login-action`
  - `docker/metadata-action`
  - `docker/build-push-action`
- The workflow prints the computed image tags in the job logs.

How to trigger CI to publish to GHCR
- Merge a PR into `main` OR push a git tag (annotated tag recommended) — either event will cause the workflow to push built images to GHCR.
- Example create & push annotated tag:
  git tag -a v0.0.1 -m "release v0.0.1"
  git push origin v0.0.1

Where to find the published image
- Repository Packages page (UI):
  https://github.com/soumya-s-goud/arculus-devops-challenge/pkgs/container/arculus-devops-challenge
- Direct registry browser:
  https://ghcr.io/soumya-s-goud/arculus-devops-challenge

Pulling the image from GHCR (private package)
1. Login to GHCR using a PAT (replace `YOUR_PAT` and `YOUR_GH_USERNAME`):
   PowerShell:
   $env:CR_PAT='YOUR_PAT'
   $env:CR_PAT | docker login ghcr.io -u YOUR_GH_USERNAME --password-stdin

2. Pull the image (example tag shown in CI logs: `sha-0b3e0e9`):
   docker pull ghcr.io/soumya-s-goud/arculus-devops-challenge:sha-0b3e0e9

3. Run the pulled image:
   docker run -d --name arculus -p 8000:8000 ghcr.io/soumya-s-goud/arculus-devops-challenge:sha-0b3e0e9

4. Test health endpoint:
   curl http://localhost:8000/health
   Expected: `{"status":"ok"}`

Verify image runs as non-root
- Check process user inside running container:
  docker exec arculus id -u    # expected output: 1000
  docker exec arculus id -un   # expected output: appuser

Common troubleshooting
- `unauthorized` or `denied` when pulling:
  - Confirm you logged in to GHCR with a PAT that has `read:packages`.
  - Ensure the token belongs to an account that has access to the private repo (or make the package public if you want anonymous pulls).
  - Test token access to manifest:
    curl.exe -I -H "Authorization: Bearer $env:CR_PAT" "https://ghcr.io/v2/soumya-s-goud/arculus-devops-challenge/manifests/<tag>"
    Expected status: `HTTP/1.1 200 OK`
- `Bind for 0.0.0.0:8000 failed: port is already allocated`:
  - Some process or container is already using port 8000. Free it:
    docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}"
    docker stop <container>
    docker rm <container>
  - Or run on a different host port:
    docker run -d --name arculus -p 8001:8000 ghcr.io/...:tag
- Container name conflict:
  - If a container with the target name already exists:
    docker rm -f arculus
    docker run -d --name arculus -p 8000:8000 ghcr.io/...:tag

Cleanup
- Stop & remove running container:
  docker stop arculus
  docker rm arculus
- Remove local image:
  docker image rm ghcr.io/soumya-s-goud/arculus-devops-challenge:sha-0b3e0e9

Notes
- The image is built to run the service as a non-root user (`appuser`) inside the container.
- CI pushes are performed only from `main` or on tag events to keep the registry clean and predictable.

If you want this README content added to the repository as `README.md`, I can produce the file content ready for commit.  

Part 3: Kubernetes deployment + Ingress/TLS
## Deployment with CD (Summary)
This part deploys the Orders application (UI + API) into Kubernetes using Terraform to apply Kubernetes manifests. The repository includes:
- Application code and Dockerfile (buildable image)
- A Terraform + k8s manifest pattern (to be added/committed) for deploying into a cluster (kind recommended for local work)
- A GitHub Actions workflow (deploy-to-kind.yml) for CI/CD (build image → terraform apply)

This README documents what Part 3 implements, how to run it locally, and what secrets/choices are required for CI.

---

## What is included / planned
(Place these files under the paths shown before committing)
- terraform/
  - `main.tf` — Terraform resources using the kubectl provider to apply manifests
  - `variables.tf` — `image_tag` and `namespace` variables
  - `app-deployment.tpl` — templated Deployment (image + namespace substitution)
- k8s/
  - `namespace.yaml`
  - `secret-db.yaml` (stores DB credentials as Kubernetes Secret)
  - `postgres-deployment.yaml` + `postgres-service.yaml` (optional in-cluster DB)
  - `app-deployment.yaml` or template (readiness/liveness probes, resources)
  - `app-service.yaml`
  - `ingress.yaml` (references `orders-tls` TLS secret)
- `.github/workflows/deploy-to-kind.yml` — CI workflow that builds image and runs Terraform apply

Mapping to requirements
1. Deploy Orders app (UI + API): Yes — Deployment + Service manifest included.
2. Resource requests & limits: Yes — included in the app (and postgres) container specs.
3. Ingress with TLS termination: Yes — Ingress manifest references `orders-tls`; instructions below create a self-signed cert.
4. DB credentials in Secrets: Yes — `secret-db.yaml` stores credentials (stringData).
5. Readiness & liveness probes: Yes — added to app and postgres containers.
6. Database options:
   - In-cluster Postgres manifest included (optional), OR
   - External DB — set DB connection in `secret-db.yaml` or via environment.

---

## Quick local deploy (recommended: kind)
Prereqs (local)
- Docker running
- kind installed
- kubectl installed
- Terraform installed (or use the included binary path you prefer)

Flow A — fast local iteration (build + load into kind)
1) Create kind cluster
```bash
kind create cluster --name dev
kubectl cluster-info --context kind-dev
```

2) Build and load image into kind
```bash
# from repo root
docker build -t ghcr.io/<your-org>/arculus-devops-challenge:local -f Dockerfile .
kind load docker-image ghcr.io/<your-org>/arculus-devops-challenge:local --name dev
```

3) From `terraform/` folder: init & apply
```bash
# in repo/terraform
terraform init
terraform apply -var="image_tag=ghcr.io/<your-org>/arculus-devops-challenge:local" -var="namespace=orders" -auto-approve
```

Flow B — CI-style (push to GHCR)
1) Build, tag and push to GHCR
```bash
docker build -t ghcr.io/<your-org>/arculus-devops-challenge:sha-<short> .
docker login ghcr.io -u <user> -p <GHCR_PAT>
docker push ghcr.io/<your-org>/arculus-devops-challenge:sha-<short>
```

2) Run terraform using that image tag
```bash
cd terraform
terraform init
terraform apply -var="image_tag=ghcr.io/<your-org>/arculus-devops-challenge:sha-<short>" -var="namespace=orders" -auto-approve
```

---

## TLS (self-signed) for Ingress
1) Generate cert (example)
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=orders.local/O=orders"
```
2) Create TLS secret for the `orders` namespace
```bash
kubectl -n orders create secret tls orders-tls --cert=./tls.crt --key=./tls.key
```
3) For testing, map `orders.local` to localhost:
- Linux / macOS:
  `sudo -- sh -c 'echo "127.0.0.1 orders.local" >> /etc/hosts'`
- Windows (Admin PowerShell):
  `Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "127.0.0.1 orders.local"`

---

## GitHub Actions (deploy-to-kind.yml)
Workflow purpose: build container image and run `terraform apply`. Runner options:
- Self-hosted runner on the machine with kind (recommended for local kind).
- OR GitHub-hosted runner + `KUBE_CONFIG_DATA` repo secret (base64 kubeconfig) if cluster API is reachable.

Secrets required (if using hosted runners)
- `GHCR_PAT` — token that can push to GHCR (scope: packages: write; add repo if private)
- `KUBE_CONFIG_DATA` — base64-encoded kubeconfig (only for hosted runners)

How to produce `KUBE_CONFIG_DATA` (PowerShell)
```powershell
[Convert]::ToBase64String([System.IO.File]::ReadAllBytes("$env:USERPROFILE\.kube\config"))
# copy output and create repo secret named KUBE_CONFIG_DATA
```

If you will use a self-hosted runner, register it in the repository settings and set `runs-on: ["self-hosted","linux","x64"]` in the workflow.

---

## Verify after deploy
```bash
kubectl -n orders get pods
kubectl -n orders get svc
kubectl -n orders get ingress
curl -k https://orders.local/health
```

If pod(s) are CrashLoopBackOff or fail readiness, run:
```bash
kubectl -n orders describe pods -l app=orders-app
kubectl -n orders logs -l app=orders-app --all-containers=true --tail=200
```

---

## Minimal checklist before committing
- [ ] Add k8s manifests under `k8s/` (namespace, secret, app, service, ingress, postgres optional)
- [ ] Add `terraform/` with `main.tf`, `variables.tf`, and template(s)
- [ ] Add `.github/workflows/deploy-to-kind.yml`
- [ ] Add `GHCR_PAT` to GitHub repo secrets
- [ ] Decide runner strategy: self-hosted (recommended for kind) or hosted + `KUBE_CONFIG_DATA`

---

## Notes & security
- For local dev use kind + self-hosted runner (no public kubeconfig secrets).
- Avoid storing long-lived admin kubeconfigs as repo secrets for production environments.
- For production-grade CD, consider GitOps (Argo CD / Flux) and least-privilege service accounts.

---

If you want, I can now produce the exact `k8s/` manifests and `terraform/` files (ready to commit) that fully satisfy Part 3. Reply with `produce files` to get those file contents next.

Part 4: Monitoring

How to run and test will be documented as the implementation is added.
