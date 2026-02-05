# Arculus DevOps Challenge – Orders API

DevOps Engineer (Linux) technical challenge submission: **Python Orders service** with CI, containerization, Kubernetes deployment, Terraform IaC, and monitoring.

This repository is organised to reflect a **GitOps** approach: application code, Kubernetes manifests, Terraform, and monitoring assets are all in version control.

---

## 1. Problem Overview

We implement a simple **Orders API** in Python:

- Each order has:
  - `id` – unique identifier.
  - `amount` – monetary value.
- Requirements:
  - Minimal **web UI** showing stored orders.
  - `/orders` API to create and retrieve orders (persisted in a DB).
  - `/health` endpoint for health checks.
  - Orders persisted in **PostgreSQL**.

This application is the basis for demonstrating:

- Part 1 – Application & CI (tests, linting, coverage, .deb packaging)  
- Part 2 – Dockerization & Registry (multi-stage, non-root image, GHCR)  
- Part 3 – Kubernetes & CD (manifests + Terraform + GitHub Actions)  
- Part 4 – Monitoring (Prometheus + Grafana)  
- Part 5 – Security (non-root, secrets; mTLS documented as future work)

---

## 2. Repository Layout

```text
.
├─ apps/                     # Python Flask Orders API + UI
│  ├─ __init__.py
│  ├─ main.py                # App entrypoint (Flask app, /health, /orders, UI)
│  └─ templates/             # HTML templates for orders UI
│
├─ tests/                    # Unit + integration tests
│  ├─ unit/
│  └─ integration/
│
├─ k8s/                      # Kubernetes manifests for Orders stack
│  ├─ namespace.yaml         # orders namespace
│  ├─ secret-db.yaml         # DATABASE_URL + DB credentials (K8s Secret)
│  ├─ postgres-deployment.yaml
│  ├─ postgres-service.yaml
│  ├─ app-deployment.yaml    # Orders app Deployment (uses GHCR image)
│  ├─ app-service.yaml       # Orders app Service (ClusterIP)
│  └─ ingress.yaml           # Ingress with TLS for orders.local
│
├─ terraform/                # Terraform module wrapping K8s manifests
│  ├─ main.tf                # Uses gavinbunney/kubectl to apply namespace/secret/DB/svc/ingress
│  ├─ variables.tf           # image_tag, namespace
│  ├─ app-deployment.tpl     # Templated app Deployment (reference)
│  └─ .terraform.lock.hcl    # Provider lock (gavinbunney/kubectl)
│
├─ .github/
│  └─ workflows/             # GitHub Actions CI/CD workflows
│     ├─ ci.yml              # Build & test, coverage, .deb packaging
│     ├─ docker-ci.yml       # Docker build & push to GHCR
│     ├─ deploy-to-kind.yml  # CD to kind using raw manifests + smoke test
│     ├─ deploy-with-terraform.yml # CD to kind using Terraform + kubectl app deploy
│     └─ monitoring.yml      # Deploy app + kube-prometheus-stack (Prometheus + Grafana)
│
├─ Dockerfile                # Multi-stage, non-root image for Orders API
├─ requirements.txt          # Python dependencies
├─ setup.cfg                 # Linting / pytest / tooling config
├─ .gitignore
├─ .dockerignore
└─ README.md                 # Challenge description, setup, demo instructions
```

Key directories:

- `apps/` – Flask app with:
  - `/health` endpoint.
  - `/orders` API (create + list).
  - HTML template to render stored orders.
- `tests/` – pytest tests including:
  - Unit tests.
  - Integration tests verifying DB connection + `/orders`.
- `k8s/` – K8s assets:
  - `namespace.yaml`
  - `secret-db.yaml`
  - `postgres-deployment.yaml`
  - `postgres-service.yaml`
  - `app-deployment.yaml`
  - `app-service.yaml`
  - `ingress.yaml`
- `terraform/` – Terraform using `gavinbunney/kubectl` to apply the above K8s resources:
  - `main.tf`, `variables.tf`, `app-deployment.tpl`, `.terraform.lock.hcl`.

---

## 3. Part 1 – Application Development & CI

### 3.1 Application features

Implementation (Flask) lives in `apps/`:

- **Minimal UI**
  - `GET /` renders a page listing all orders from the database (HTML template).
- **Health endpoint**
  - `GET /health` returns application health (simple 200 JSON).
- **Orders API**
  - `GET /orders` – list all orders (id, amount).
  - `POST /orders` – create a new order (id, amount).
- **Persistence**
  - Uses PostgreSQL, configured via `DATABASE_URL`.
  - In Kubernetes, this is provided by `k8s/secret-db.yaml`:
    - `DATABASE_URL: "postgresql://ordersuser:orders-pass@postgres.orders.svc.cluster.local:5432/ordersdb"`

### 3.2 CI – linting, tests, coverage, .deb

**Workflow:** `.github/workflows/ci.yml`  
**Name:** `CI Workflow - Build & Test Debian Package`

What it does:

- Installs dependencies from `requirements.txt`.
- Runs **linting** (configured in `setup.cfg` – e.g. flake8/pylint rules).
- Runs **unit + integration tests** with `pytest`:
  - Integration tests start a Postgres service and hit `/orders`.
- Generates **coverage reports** (HTML via `pytest-cov`) and uploads them as artifacts.
- Builds a **Debian package (.deb)**:
  - Installs the app into `/opt/...`.
  - Creates a `systemd` unit to run the webserver.
  - Publishes the `.deb` as a workflow artifact.

**Triggers:**

- On push to any branch.
- On pull requests.

**How to run tests locally:**

```bash
# From repo root
pip install -r requirements.txt
pytest tests/ --cov=apps --cov-report=html
# Open htmlcov/index.html for coverage
```

---

## 4. Part 2 – Dockerization & Registry

### 4.1 Dockerfile

**File:** [`Dockerfile`](./Dockerfile)

Key properties:

- **Multi-stage build**:
  - `builder` stage:
    - Installs build deps (`build-essential`, `gcc`, `libpq-dev`).
    - Installs Python deps + `gunicorn` into a separate `/install` prefix.
  - `runtime` stage:
    - Based on `python:3.9-slim`.
    - Copies only installed artifacts from `/install` → smaller image.
- **Non-root user**:
  - Creates `appuser`.
  - Sets `USER appuser`.
- **Entrypoint**:
  - Uses `gunicorn`:
    - `CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "apps.main:app"]`

### 4.2 Docker CI – build & push to GHCR

**Workflow:** `.github/workflows/docker-ci.yml`  
**Name:** `Docker build & push`

What it does:

- Builds the multi-stage image from `Dockerfile`.
- Pushes to **GitHub Container Registry (GHCR)**:
  - `ghcr.io/soumya-s-goud/arculus-devops-challenge:<git-sha>`
  - `ghcr.io/soumya-s-goud/arculus-devops-challenge:latest`
- Uses buildx + cache to speed up builds.

**Image registry location:**

- [GHCR packages for this repo](https://github.com/users/soumya-s-goud/packages?repo=soumya-s-goud%2Farculus-devops-challenge)  
  → Select `arculus-devops-challenge` to see tags.

---

## 5. Part 3 – Deployment with CD (Kubernetes + Terraform)

We use **kind** as the Kubernetes cluster in CI and for local testing.

### 5.1 Kubernetes manifests (`k8s/`)

- `namespace.yaml` – `orders` namespace.
- `secret-db.yaml` – database credentials + `DATABASE_URL` secret.
- `postgres-deployment.yaml` – in-cluster Postgres with liveness/readiness probes.
- `postgres-service.yaml` – ClusterIP service for Postgres.
- `app-deployment.yaml` – Orders app Deployment:
  - Uses `ghcr.io/soumya-s-goud/arculus-devops-challenge:latest`.
  - **Resources**:
    - Requests: 100m CPU, 128Mi RAM.
    - Limits: 250m CPU, 256Mi RAM.
  - **Probes**:
    - Liveness & readiness on `GET /health` port `8000`.
  - **Security**:
    - `runAsNonRoot: true`, `runAsUser: 1000`.
  - **Secrets**:
    - `DATABASE_URL` from `orders-db-credentials`.
  - **Image pull**:
    - Configured to use an `imagePullSecrets` entry for GHCR (created in workflow).
- `app-service.yaml` – ClusterIP service exposing the app on port `8000`.
- `ingress.yaml` – Ingress for `orders.local` with TLS (`orders-tls` secret):
  - TLS termination at ingress (self-signed acceptable).
  - Routes traffic to `orders` service.

### 5.2 Terraform module (`terraform/`)

Files:

- `terraform/main.tf`  
- `terraform/variables.tf`  
- `terraform/app-deployment.tpl`  
- `terraform/.terraform.lock.hcl`

What it does:

- Uses `gavinbunney/kubectl` provider to:
  - Create the namespace.
  - Apply all K8s resources via `kubectl_manifest`:
    - DB secret, Postgres Deployment/Service, Orders app Deployment/Service, Ingress.
- Reads the YAML manifests from `k8s/` and injects `namespace` dynamically.
- Uses `app-deployment.tpl` to template the Orders Deployment:
  - `image: ghcr.io/soumya-s-goud/arculus-devops-challenge:${image_tag}`
  - Same resources, probes, and security context as the raw manifest.

### 5.3 CD – direct manifests to kind

**Workflow:** `.github/workflows/deploy-to-kind.yml`  
**Name:** `deploy-to-kind`

Steps:

1. **Build & push image** (via `needs: build` job) → GHCR `:latest` and `:<sha>`.
2. **Set up kind cluster** (`deploy-kind`).
3. **Install kubectl** (v1.27.0).
4. **Create GHCR image pull secret** in `orders` namespace using `GITHUB_TOKEN`.
5. **Apply manifests** with `kubectl`:
   - `k8s/namespace.yaml`
   - `k8s/secret-db.yaml`
   - `k8s/postgres-deployment.yaml`
   - `k8s/postgres-service.yaml`
   - `k8s/app-deployment.yaml`
   - `k8s/app-service.yaml`
   - `k8s/ingress.yaml`
6. **Wait for rollout** of Postgres and Orders app (logs if timeouts occur).
7. **Smoke test `/health`**:
   - Starts a `busybox` pod in `orders` namespace:
     - Tries `GET /health` on `http://orders:8000/health` up to 30 times.
   - Fails the job if the app isn’t reachable.

### 5.4 CD – Terraform-based deployment to kind

**Workflow:** `.github/workflows/deploy-with-terraform.yml`  
**Name:** `deploy-with-terraform`

Steps:

1. Spin up a kind cluster (`terraform-kind`).
2. Install kubectl + Terraform.
3. Run:
   - `terraform init`
   - `terraform apply -auto-approve -var="image_tag=latest" -var="namespace=orders"`
4. Smoke test `/health` from inside the cluster (similar busybox pattern).

This workflow satisfies the requirement to **“use Terraform (Helm or manifest inside Terraform) for deployment”**.

---

## 6. Part 4 – Monitoring & Logging

### 6.1 Monitoring stack: Prometheus + Grafana

**Workflow:** `.github/workflows/monitoring.yml`  
**Name:** `deploy-monitoring-ci`

Steps:

1. Create a kind cluster (`monitoring-kind`).
2. Deploy the full Orders stack (namespace, DB, app, service, ingress) via K8s manifests.
3. Wait for Postgres & Orders app (with debug logs on timeouts).
4. Smoke test `/health` using a `busybox` pod.
5. Install **kube-prometheus-stack** via Helm:
   - Chart: `prometheus-community/kube-prometheus-stack`
   - Namespace: `monitoring`
   - Grafana enabled.
6. Verify monitoring components:
   - `kubectl get pods -n monitoring`
   - `kubectl get svc -n monitoring`

This provides:

- **Prometheus** – cluster & app metrics.
- **Grafana** – dashboards.

If you add:

- `monitoring/alerts-orders.yaml` – example `PrometheusRule` for:
  - HTTP 5xx rate.
  - p95 latency.
  - DB connection errors.
- `monitoring/grafana-orders-dashboard.json` – sample dashboard JSON.

…these files serve as the **“Monitoring artifacts (Grafana dashboard JSON, alert rules)”** requested in the challenge.

### 6.2 Local access to Prometheus & Grafana

After deploying monitoring (either via the workflow or locally):

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then:

- Grafana: http://localhost:3000  
- Prometheus: http://localhost:9090

To import a dashboard:

- Grafana → Dashboards → Import → upload `monitoring/grafana-orders-dashboard.json`.

---

## 7. Part 5 – Security (Optional)

What is implemented:

- **Non-root containers**:
  - Dockerfile: `USER appuser`.
  - K8s Deployment: `securityContext.runAsNonRoot: true`, `runAsUser: 1000`.
- **Secrets not in Docker image or code**:
  - DB credentials and `DATABASE_URL` stored in `k8s/secret-db.yaml`, not in the image or Python source.

What is **not implemented** (by design, due to timebox):

- **mTLS between application and database**:
  - No client/server certificates or TLS configuration for Postgres.
  - This is called out as a future improvement.

---

## 8. Running Locally (minikube/kind) – Reproducible Steps

### 8.1 Prerequisites

- Python 3.9+
- Docker
- `kubectl`
- `helm`
- `kind` (or minikube/k3s, but examples use kind)
- Terraform (for Terraform-based deployment)

### 8.2 Local app + Postgres (no Kubernetes)

```bash
# Start Postgres
docker run --name orders-postgres -e POSTGRES_DB=ordersdb \
  -e POSTGRES_USER=ordersuser \
  -e POSTGRES_PASSWORD=orders-pass \
  -p 5432:5432 -d postgres:15-alpine

# Set DATABASE_URL
export DATABASE_URL="postgresql://ordersuser:orders-pass@localhost:5432/ordersdb"

# Install deps and run app
pip install -r requirements.txt
python -m apps.main  # or: gunicorn -w 4 -b 0.0.0.0:8000 apps.main:app

# Access locally
curl http://localhost:8000/health
curl http://localhost:8000/orders
```

### 8.3 Local Kubernetes deployment with manifests

```bash
# Create kind cluster
kind create cluster --name orders-local

# Apply manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret-db.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/ingress.yaml

# Check status
kubectl get pods,svc,deploy,ingress -n orders

# Health from inside cluster
kubectl run curl -n orders --image=busybox:1.36 --restart=Never -- \
  sh -c 'wget -qO- http://orders:8000/health'
```

To access via Ingress:

- Add to `/etc/hosts`:

  ```text
  127.0.0.1 orders.local
  ```

- Then open:
  - http://orders.local/ (UI)
  - http://orders.local/health (health)

### 8.4 Local Kubernetes deployment with Terraform

```bash
# Create kind cluster
kind create cluster --name orders-terraform

cd terraform
terraform init
terraform apply -auto-approve \
  -var="image_tag=latest" \
  -var="namespace=orders"

# Back in repo root
kubectl get pods,svc,deploy,ingress -n orders
kubectl run curl -n orders --image=busybox:1.36 --restart=Never -- \
  sh -c 'wget -qO- http://orders:8000/health'
```

### 8.5 Local monitoring (Prometheus + Grafana)

```bash
# With orders stack already deployed

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=true \
  --wait
```

Then:

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Port-forward Grafana and Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

- Grafana: http://localhost:3000  
- Prometheus: http://localhost:9090

---

## 9. CI/CD Pipelines – How to Run & What They Show

### 9.1 CI – Build & Test Debian Package

- Workflow: `.github/workflows/ci.yml`  
- Runs on push/PR.  
- Artifacts:
  - Coverage HTML report.
  - .deb package.

### 9.2 Docker image build & push

- Workflow: `.github/workflows/docker-ci.yml`  
- Builds multi-stage Docker image and pushes to GHCR with `latest` and SHA tags.

### 9.3 CD – deploy-to-kind (manifests)

- Workflow: `.github/workflows/deploy-to-kind.yml`  
- Creates a kind cluster, deploys the Orders stack with `kubectl apply`, waits for rollouts, and tests `/health`.

### 9.4 CD – deploy-with-terraform (Terraform IaC)

- Workflow: `.github/workflows/deploy-with-terraform.yml`  
- Creates a kind cluster, runs `terraform apply` in `terraform/`, and tests `/health`.

### 9.5 Monitoring – deploy-monitoring-ci

- Workflow: `.github/workflows/monitoring.yml`  
- Creates a kind cluster, deploys the Orders stack, installs kube-prometheus-stack, and tests `/health`.

---

## 10. Assumptions & Limitations

- **Cluster type**: All automation assumes an ephemeral kind cluster in CI; adapting to long-lived clusters is straightforward but out of scope.
- **Database**: Postgres runs as a K8s Pod inside the cluster (acceptable per challenge, though external DB is “preferred” in the prompt).
- **mTLS**: End-to-end mTLS between app and DB is **not implemented**. It’s documented here as future work.
- **Monitoring**:
  - Prometheus + Grafana are deployed and verifiable.
  - Example alert rules and dashboards can be versioned under `monitoring/`, but wiring to real app metrics is kept minimal for the timebox.
- **Secrets**:
  - DB credentials are in `k8s/secret-db.yaml` as an example K8s Secret manifest; in a real GitOps setup they would be managed via a secret manager or sealed secrets.

---
