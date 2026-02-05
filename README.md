# Arculus DevOps Challenge – Orders API

DevOps Engineer (Linux) technical challenge submission: **Python Orders service** with CI, containerization, Kubernetes deployment, Terraform IaC, and monitoring.

This repository is organised to reflect a **GitOps** approach: application code, Kubernetes manifests, Terraform, and monitoring assets are all in version control and automated via GitHub Actions.

---

## 1. Problem Overview & Architecture

We implement a simple **Orders API** in Python:

- Each order has:
  - `id` – unique identifier.
  - `amount` – monetary value.
- Requirements:
  - Minimal **web UI** showing stored orders.
  - `/orders` API to create and retrieve orders (persisted in a DB).
  - `/health` endpoint for health checks.
  - Orders persisted in **PostgreSQL**.

The app, database, and ingress sit in the `orders` namespace and are deployed to Kubernetes via manifests and Terraform, with CI/CD using GitHub Actions. Monitoring is provided via the `kube-prometheus-stack` Helm chart (Prometheus + Grafana) in a `monitoring` namespace.

### 1.1 Simplified Architecture Diagram

```text
                   ┌──────────────────────────────────────────┐
                   │              GitHub Actions              │
                   │  - CI (lint, tests, coverage, .deb)     │
                   │  - Docker build & push (GHCR)           │
                   │  - CD (kubectl / Terraform to kind)     │
                   │  - Monitoring stack deployment          │
                   └──────────────────────────────────────────┘
                                      │
                                      ▼
                         (ephemeral kind clusters in CI)
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster (kind)                         │
│                                                                           │
│  Namespace: orders                                                        │
│  ┌─────────────────────────────┐      ┌─────────────────────────────┐     │
│  │  Deployment: postgres       │      │ Deployment: orders-app      │     │
│  │  Service: postgres          │      │ Service: orders             │     │
│  │  (DB Pod)                   │      │ (UI + /health + /orders)    │     │
│  └─────────────────────────────┘      └─────────────────────────────┘     │
│              ▲                                  ▲                        │
│              │                                  │                        │
│      Secret: orders-db-credentials              │                        │
│      (DATABASE_URL, DB_USER, DB_PASSWORD)       │                        │
│              │                                  │                        │
│              └────────────► App uses DATABASE_URL env var                │
│                                                                           │
│  Ingress (orders-ingress)                                                │
│  - Host: orders.local                                                    │
│  - TLS: orders-tls (self-signed; created in CD workflows)               │
│  - Routes /, /health, /orders → Service: orders                          │
└───────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────────┐
│                       Namespace: monitoring                               │
│  kube-prometheus-stack (Helm)                                            │
│  - Prometheus, Alertmanager, Grafana                                     │
│  - App-specific PrometheusRule (alerts-orders.yaml)                      │
│  - Grafana dashboard JSON (grafana-orders-dashboard.json)                │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Repository Layout

```text
.
├─ apps/                     # Python Flask Orders API + UI
│  ├─ __init__.py
│  ├─ main.py                # App entrypoint (/health, /orders, UI)
│  └─ templates/             # HTML templates for orders UI
│
├─ tests/                    # Unit + integration tests
│  ├─ unit/
│  └─ integration/
│
├─ k8s/                      # Kubernetes manifests for Orders stack
│  ├─ namespace.yaml         # orders namespace
│  ├─ secret-db.yaml         # Example DB Secret (dummy credentials)
│  ├─ postgres-deployment.yaml
│  ├─ postgres-service.yaml
│  ├─ app-deployment.yaml    # Orders app Deployment (uses GHCR image)
│  ├─ app-service.yaml       # Orders app Service (ClusterIP)
│  └─ ingress.yaml           # Ingress with TLS for orders.local
│
├─ terraform/                # Terraform module wrapping K8s manifests
│  ├─ main.tf                # Uses gavinbunney/kubectl for namespace/secret/DB/svc/ingress
│  ├─ variables.tf           # image_tag, namespace
│  ├─ app-deployment.tpl     # Templated app Deployment (reference)
│  └─ .terraform.lock.hcl    # Provider lock (gavinbunney/kubectl)
│
├─ monitoring/               # Monitoring artifacts (sample alerts/dashboards)
│  ├─ alerts-orders.yaml     # PrometheusRule (example app-level alert rules)
│  └─ grafana-orders-dashboard.json  # Example Grafana dashboard JSON
│
├─ .github/
│  └─ workflows/             # GitHub Actions CI/CD workflows
│     ├─ ci.yml              # Build & test, coverage, .deb packaging, linting, manifest validate
│     ├─ docker-ci.yml       # Docker build & push to GHCR
│     ├─ deploy-to-kind.yml  # CD to kind (kubectl) + secrets + TLS + smoke test + logs
│     ├─ deploy-with-terraform.yml # CD to kind (Terraform + kubectl app deploy) + secrets + TLS
│     └─ monitoring.yml      # Deploy app + kube-prometheus-stack + Orders alerts
│
├─ Dockerfile                # Multi-stage, non-root image for Orders API
├─ requirements.txt          # Python dependencies
├─ setup.cfg                 # Linting / pytest / tooling config
├─ .gitignore
├─ .dockerignore
└─ README.md
```

---

## 3. Part 1 – Application Development & CI

### 3.1 Application features

Implementation (Flask) in `apps/`:

- **Minimal UI**
  - `GET /` – renders a page listing all orders from the database.
- **Health endpoint**
  - `GET /health` – returns 200 OK with a simple JSON/response for health checks.
- **Orders API**
  - `GET /orders` – list all orders (`id`, `amount`).
  - `POST /orders` – create a new order (JSON payload with `id`, `amount`).
- **Persistence**
  - Uses PostgreSQL, via `DATABASE_URL`.
  - In Kubernetes, `DATABASE_URL` is injected from the `orders-db-credentials` Secret.

### 3.2 CI – linting, tests, coverage, .deb

**Workflow:** `.github/workflows/ci.yml`  
**Name:** `CI Workflow - Build & Test Debian Package`  
**Actions link (branch `part4-monitoring`):**  
https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22CI+Workflow+-+Build+%26+Test+Debian+Package%22+branch%3Apart4-monitoring

What it does:

- **Dependencies:**
  - Installs from `requirements.txt`.
  - Installs `pytest`, `pytest-cov`, and `flake8`.

- **Linting:**
  - Step `Lint with flake8`:
    ```bash
    flake8 apps tests
    ```

- **Database service & connectivity:**
  - Starts a `postgres:15` service using GitHub Actions `services` with env from GitHub Secrets:
    - `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_PORT`.
  - Waits for readiness using `pg_isready`.
  - Runs a SQL command `SELECT version();` to verify DB connectivity.

- **Start app & HTTP integration tests:**
  - Starts `python apps/main.py` in the background.
  - Polls `/health` until ready.
  - Explicitly hits:
    - `GET /health` (health check).
    - `GET /orders` (should return 200).
    - `POST /orders` with JSON payload, then `GET /orders` again:
      ```bash
      curl -v http://localhost:5000/health
      curl -v http://localhost:5000/orders
      curl -X POST -H "Content-Type: application/json" \
           -d '{"id": "ci-test-1", "amount": 123.45}' \
           http://localhost:5000/orders
      curl -v http://localhost:5000/orders
      ```
  - This explicitly tests **/orders** end-to-end over HTTP in CI.

- **Tests + coverage:**
  - `pytest tests/ --cov=apps --cov-report=term-missing --cov-report=html:htmlcov -v`.
  - Verifies `htmlcov/index.html` exists and is non-empty.
  - Uploads `coverage-html-zip` artifact.

- **Debian package (.deb):**
  - Builds `debian_package.deb` containing:
    - Installed app under `/opt/arculus`.
    - `arculus.service` systemd unit in `/etc/systemd/system`.
  - Installs the `.deb` on the CI runner to verify:
    - `/opt/arculus` exists.
    - `arculus.service` exists.
  - Uploads `.deb` artifact as `arculus.deb`.

- **Manifest validation:**
  - Separate job `validate-manifests` installs `kubeconform` and runs:
    ```bash
    kubeconform -strict -ignore-missing-schemas -summary k8s/*.yaml
    ```
  - This adds a **Kubernetes manifest validation** phase to CI.

**Triggers:**

- `push` to `main`, `part*`, `feature/**`
- `pull_request` to the same branches

---

## 4. Part 2 – Dockerization & Registry

### 4.1 Dockerfile

**File:** [`Dockerfile`](./Dockerfile)

Key properties:

- Multi-stage build:
  - Builder with build dependencies and Python libraries.
  - Slim runtime image with just what’s needed.
- Non-root:
  - Creates `appuser`, sets `USER appuser`.
- Entrypoint:
  - `gunicorn -w 4 -b 0.0.0.0:8000 apps.main:app`.

### 4.2 Docker CI – build & push to GHCR

**Workflow:** `.github/workflows/docker-ci.yml`  
**Name:** `Docker build & push`  
**Actions:**  
https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22Docker+build+%26+push%22+branch%3Apart4-monitoring

What it does:

- Builds the multi-stage Docker image.
- Pushes to GHCR:
  - `ghcr.io/soumya-s-goud/arculus-devops-challenge:<git-sha>`
  - `ghcr.io/soumya-s-goud/arculus-devops-challenge:latest`

GHCR packages UI:  
https://github.com/users/soumya-s-goud/packages?repo=soumya-s-goud%2Farculus-devops-challenge

---

## 5. Part 3 – Deployment with CD (Kubernetes + Terraform)

We use **kind** as the cluster in CI and for local runs.

### 5.1 Kubernetes manifests (`k8s/`)

- `namespace.yaml`: defines the `orders` namespace.
- `secret-db.yaml`: **example** K8s Secret manifest for DB credentials + `DATABASE_URL`.
  - **Important note:**  
    - For demonstration, **dummy credentials** are shown in this file to indicate the schema and key names.  
    - Real credentials are **not** taken from this file in CI/CD.  
    - In CI/CD, the `orders-db-credentials` Secret is created dynamically from **GitHub Secrets** (`DB_USER`, `DB_PASSWORD`, `DB_NAME`) to avoid committing real values to git.
- `postgres-deployment.yaml` / `postgres-service.yaml`: Postgres DB Pod + Service.
- `app-deployment.yaml`:
  - Image: `ghcr.io/soumya-s-goud/arculus-devops-challenge:latest`.
  - `securityContext`:
    - `runAsNonRoot: true`, `runAsUser: 1000`.
  - `resources`:
    - Requests: `cpu: 100m`, `memory: 128Mi`.
    - Limits: `cpu: 250m`, `memory: 256Mi`.
  - `readinessProbe` / `livenessProbe`:
    - `httpGet` on `/health` port `8000`.
  - `env`:
    - `DATABASE_URL` from `orders-db-credentials` Secret.
  - `imagePullSecrets`:
    - `ghcr-pull-secret` (created at runtime by workflows).
- `app-service.yaml`: `Service` named `orders` on port `8000`.
- `ingress.yaml`:
  - `Ingress` named `orders-ingress`.
  - Host: `orders.local`.
  - TLS:
    - `secretName: orders-tls` (secret is created in CD workflows).
  - Routes `/, /health, /orders` to service `orders`.

### 5.2 Secret & TLS creation in CD workflows

In both `deploy-to-kind.yml` and `deploy-with-terraform.yml`:

- **DB Secret** is created from GitHub Secrets (no real credentials in git):

  ```bash
  kubectl create namespace orders || true
  kubectl delete secret orders-db-credentials -n orders --ignore-not-found=true
  kubectl create secret generic orders-db-credentials -n orders \
    --from-literal=DB_USER='${{ secrets.DB_USER }}' \
    --from-literal=DB_PASSWORD='${{ secrets.DB_PASSWORD }}' \
    --from-literal=DB_NAME='${{ secrets.DB_NAME }}' \
    --from-literal=DATABASE_URL="postgresql://${{ secrets.DB_USER }}:${{ secrets.DB_PASSWORD }}@postgres.orders.svc.cluster.local:5432/${{ secrets.DB_NAME }}"
  ```

- **TLS Secret** is created with a short-lived self-signed certificate:

  ```bash
  kubectl delete secret orders-tls -n orders --ignore-not-found=true
  openssl req -x509 -nodes -days 7 -newkey rsa:2048 \
    -subj "/CN=orders.local/O=Arculus" \
    -keyout orders.key -out orders.crt
  kubectl create secret tls orders-tls -n orders \
    --cert=orders.crt --key=orders.key
  rm -f orders.crt orders.key
  ```

This:

- Demonstrates TLS termination at the Ingress using a TLS secret.
- Avoids committing TLS material or live DB credentials to the repo.
- Uses **dummy values** in `k8s/secret-db.yaml` purely as a schema reference.

> For production, a more robust approach would integrate a secrets manager (or SealedSecrets/SOPS) and a certificate manager (e.g., cert-manager), but this setup is sufficient for the challenge.

### 5.3 Terraform module (`terraform/`)

**Files:**

- `terraform/main.tf` – uses `gavinbunney/kubectl`:
  - Creates `Namespace` resource.
  - Applies DB Secret, Postgres Deployment/Service, app Service, and Ingress via `kubectl_manifest`.
  - App Deployment is applied via `kubectl` in the workflow for clearer rollout handling.
- `terraform/variables.tf` – `image_tag`, `namespace`.
- `terraform/app-deployment.tpl` – templated Deployment (for reference).
- `terraform/.terraform.lock.hcl` – provider lock.

### 5.4 CD – direct manifests to kind

**Workflow:** `.github/workflows/deploy-to-kind.yml`  
**Name:** `deploy-to-kind`  
**Actions:**  
https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-to-kind%22+branch%3Apart4-monitoring

What it does:

1. Builds/pushes Docker image (via `build` job).
2. Creates a kind cluster (`deploy-kind`).
3. Installs kubectl.
4. Creates:
   - `orders-db-credentials` Secret from GitHub Secrets (as above).
   - `orders-tls` TLS secret from self-signed cert.
   - `ghcr-pull-secret` for GHCR authentication.
5. Applies all `k8s/*.yaml` manifests with `kubectl apply`.
6. Waits for Postgres and Orders app rollout; prints detailed logs on failure.
7. Runs `/health` smoke test from inside cluster (busybox + wget with retries).
8. Collects cluster logs (pods, services, app logs, DB logs) into `artifacts/` and uploads them as `deploy-to-kind-logs` artifact.

### 5.5 CD – Terraform-based deployment to kind

**Workflow:** `.github/workflows/deploy-with-terraform.yml`  
**Name:** `deploy-with-terraform`  
**Actions:**  
https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-with-terraform%22+branch%3Apart4-monitoring

What it does:

1. Creates a kind cluster (`terraform-kind`).
2. Installs kubectl and Terraform.
3. Creates Secrets (`orders-db-credentials`, `orders-tls`, `ghcr-pull-secret`) as above.
4. Runs `terraform init` and `terraform apply` in `terraform/`:
   - Applies namespace, DB Secret, Postgres Deployment/Service, app Service, Ingress.
5. Applies Orders app Deployment via `kubectl apply -f k8s/app-deployment.yaml`.
6. Waits for rollout; prints pod logs on failure.
7. Runs `/health` smoke test from inside the cluster (same busybox pattern).
8. Collects and uploads cluster logs as an artifact (e.g., `deploy-with-terraform-logs`).

### 5.6 Manifest validation in CI

- Job `validate-manifests` in `ci.yml`:
  - Uses `kubeconform` to validate all `k8s` manifests.
  - Enforces schema correctness before CD jobs run.

---

## 6. Part 4 – Monitoring & Logging

### 6.1 Monitoring stack: Prometheus + Grafana

**Workflow:** `.github/workflows/monitoring.yml`  
**Name:** `deploy-monitoring-ci`  
**Actions:**  
https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-monitoring-ci%22+branch%3Apart4-monitoring

What it does:

1. Creates a kind cluster (`monitoring-kind`).
2. Deploys Orders stack using `k8s/*.yaml` + Secrets + TLS (same script as `deploy-to-kind`).
3. Waits for Postgres and Orders app rollout; prints logs on failure.
4. Runs `/health` smoke test from inside the cluster.
5. Installs `kube-prometheus-stack` via Helm in `monitoring` namespace:
   ```bash
   helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace \
     --set grafana.enabled=true \
     --wait --timeout 10m
   ```
6. Applies Orders-specific PrometheusRule:
   ```bash
   kubectl apply -f monitoring/alerts-orders.yaml -n monitoring
   ```
7. Verifies monitoring components with `kubectl get pods` and `kubectl get svc` in `monitoring` namespace.

### 6.2 Monitoring artifacts: dashboards and alerts

**Directory:** `monitoring/`

- `alerts-orders.yaml`:
  - `PrometheusRule` defining example alerts for:
    - High HTTP 5xx rate on Orders API.
    - High p95 latency.
    - DB connection errors.
  - Applied automatically by `monitoring.yml` after kube-prometheus-stack install.
- `grafana-orders-dashboard.json`:
  - Example Grafana dashboard JSON:
    - Requests per second.
    - 5xx rate.
    - (Assumes standard HTTP metrics – even if the current app does not expose all of them yet, this file serves as a **sample artifact** as required by the challenge.)

### 6.3 Logging

- Logs are collected in deployment workflows via `kubectl logs` for:
  - Orders app.
  - Postgres.
- These are stored under `artifacts/` and uploaded as GitHub Actions artifacts (`deploy-to-kind-logs`, `deploy-with-terraform-logs`, etc.).
- A dedicated logging stack (Loki/ELK) is not implemented; for the challenge scope, this is acceptable.

---

## 7. Part 5 – Security (Optional) & Best Practices

- **Non-root containers**:
  - Dockerfile uses `USER appuser`.
  - `app-deployment.yaml` sets `runAsNonRoot: true`, `runAsUser: 1000`.
- **Resource limits**:
  - App and DB deployments define CPU/memory requests and limits.
- **imagePullSecrets**:
  - `ghcr-pull-secret` created in workflows from GitHub token.
- **Secrets**:
  - `k8s/secret-db.yaml` uses **dummy placeholders** to illustrate the Secret schema (key names/structure).
  - Real credentials are sourced from **GitHub Secrets** and used to create the `orders-db-credentials` Secret at runtime.
  - This avoids storing real credentials in git or Docker images.
- **mTLS**:
  - Not implemented between app and DB in this challenge submission.
  - TLS is used at the Ingress (self-signed cert via `orders-tls`), but DB traffic is plain TCP.
  - The optional Part 5 requirement for mTLS is acknowledged but deliberately not implemented due to scope/time.

---

## 8. Running Locally – Reproducible Steps

### 8.1 Prerequisites

- Python 3.9+
- Docker
- `kubectl`
- `helm`
- `kind`
- Terraform (for Terraform-based deployment)

Clone:

```bash
git clone https://github.com/soumya-s-goud/arculus-devops-challenge.git
cd arculus-devops-challenge
```

### 8.2 Local app + Postgres (no Kubernetes)

```bash
docker run --name orders-postgres -e POSTGRES_DB=ordersdb \
  -e POSTGRES_USER=ordersuser \
  -e POSTGRES_PASSWORD=orders-pass \
  -p 5432:5432 -d postgres:15-alpine

export DATABASE_URL="postgresql://ordersuser:orders-pass@localhost:5432/ordersdb"

pip install -r requirements.txt
python -m apps.main

curl http://localhost:8000/health
curl http://localhost:8000/orders
```

### 8.3 Local Kubernetes deployment with manifests (kind)

```bash
kind create cluster --name orders-local

# For local demo you can optionally apply the example secret
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret-db.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/ingress.yaml

kubectl get pods,svc,deploy,ingress -n orders

kubectl run curl -n orders --image=busybox:1.36 --restart=Never -- \
  sh -c 'wget -qO- http://orders:8000/health'
```

For TLS demo, create a self-signed `orders-tls` as in the workflows and add:

```text
127.0.0.1 orders.local
```

to `/etc/hosts`, then visit:

- http://orders.local/
- http://orders.local/health

### 8.4 Local Kubernetes with Terraform

```bash
kind create cluster --name orders-terraform

cd terraform
terraform init
terraform apply -auto-approve \
  -var="image_tag=latest" \
  -var="namespace=orders"
cd ..

kubectl apply -f k8s/app-deployment.yaml

kubectl get pods,svc,deploy,ingress -n orders
kubectl run curl -n orders --image=busybox:1.36 --restart=Never -- \
  sh -c 'wget -qO- http://orders:8000/health'
```

### 8.5 Local monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=true \
  --wait

kubectl apply -f monitoring/alerts-orders.yaml -n monitoring

kubectl get pods -n monitoring
kubectl get svc -n monitoring

kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then:

- Grafana: http://localhost:3000  
- Prometheus: http://localhost:9090  

Import `monitoring/grafana-orders-dashboard.json` into Grafana for the Orders dashboard.

---

## 9. CI/CD Pipelines – Summary & Links

- **CI – build, lint, tests, coverage, .deb:**  
  `.github/workflows/ci.yml`  
  https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22CI+Workflow+-+Build+%26+Test+Debian+Package%22+branch%3Apart4-monitoring

- **Docker build & push:**  
  `.github/workflows/docker-ci.yml`  
  https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22Docker+build+%26+push%22+branch%3Apart4-monitoring

- **CD – manifests to kind:**  
  `.github/workflows/deploy-to-kind.yml`  
  https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-to-kind%22+branch%3Apart4-monitoring

- **CD – Terraform + kubectl:**  
  `.github/workflows/deploy-with-terraform.yml`  
  https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-with-terraform%22+branch%3Apart4-monitoring

- **Monitoring – Prometheus + Grafana:**  
  `.github/workflows/monitoring.yml`  
  https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-monitoring-ci%22+branch%3Apart4-monitoring

---

## 10. Assumptions, Limitations, and Future Improvements

### Assumptions

- GHCR is accessible from CI kind clusters using `GITHUB_TOKEN` and `ghcr-pull-secret`.
- Using dummy credentials in `k8s/secret-db.yaml` is acceptable as a **schema example**; real credentials are always injected via GitHub Secrets in workflows.
- For the challenge, Postgres running in-cluster is acceptable, even if an external DB is preferred.

### Limitations

- **No self-hosted runners**: all CI/CD uses GitHub-hosted `ubuntu-latest` runners and ephemeral kind clusters.
- **HTTPS validation**: TLS (`orders-tls`) is created and used for Ingress, but CI still validates via HTTP `/health` inside the cluster; no explicit HTTPS curl is performed.
- **Monitoring metrics**: Alerts and dashboard JSON use standard HTTP metric names; full integration with an app metrics exporter is not implemented.
- **mTLS between app and DB**: not implemented; would require SSL options in `DATABASE_URL` and certificate distribution.

### Future improvements

- Integrate a secret-management solution (SOPS/SealedSecrets or external vault).
- Add HTTPS smoke tests in CI (e.g., `curl -k https://orders.local/health` via port-forward/Ingress).
- Wire app metrics into Prometheus (expose `/metrics`) to fully back all panels and alerts.
- Implement mTLS between app and DB for a production-grade security story.
