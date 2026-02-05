# Arculus DevOps Challenge - Orders API

DevOps Engineer (Linux) technical challenge submission: **Python Orders service** with CI, containerization, Kubernetes deployment, Terraform IaC, and monitoring.

This repository is organised to reflect a **GitOps** approach: application code, Kubernetes manifests, Terraform, and monitoring assets are all in version control and automated via GitHub Actions.

---

## 1. Problem Overview & Architecture

We implement a simple **Orders API** in Python:

- Each order has:
  - `id` - unique identifier.
  - `amount` - monetary value.
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
└────────────────���──────────────────────────────────────────────────────────┘

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

## 3. Part 1 - Application Development & CI

### 3.1 Application features

Implementation (Flask) in `apps/`:

- **Minimal UI**
  - `GET /` - renders a page listing all orders from the database.
- **Health endpoint**
  - `GET /health` - returns 200 OK with a simple JSON/response for health checks.
- **Orders API**
  - `GET /orders` - list all orders (`id`, `amount`).
  - `POST /orders` - create a new order (JSON payload with `id`, `amount`).
- **Persistence**
  - Uses PostgreSQL, via `DATABASE_URL`.
  - In Kubernetes, `DATABASE_URL` is injected from the `orders-db-credentials` Secret.

### 3.2 CI - linting, tests, coverage, .deb

**Workflow:** [.github/workflows/ci.yml](./.github/workflows/ci.yml)  
**Name:** `CI Workflow - Build & Test Debian Package`  
**Actions link (branch `part4-monitoring`):**  
[CI workflow runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22CI+Workflow+-+Build+%26+Test+Debian+Package%22+branch%3Apart4-monitoring)

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
    - `POST /orders` with JSON payload, then `GET /orders` again.
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

## 4. Part 2 - Dockerization & Registry

### 4.1 Dockerfile

**File:** [Dockerfile](./Dockerfile)

Key properties:

- Multi-stage build:
  - Builder with build dependencies and Python libraries.
  - Slim runtime image with just what is needed.
- Non-root:
  - Creates `appuser`, sets `USER appuser`.
- Entrypoint:
  - `gunicorn -w 4 -b 0.0.0.0:8000 apps.main:app`.

### 4.2 Docker CI - build & push to GHCR

**Workflow:** [.github/workflows/docker-ci.yml](./.github/workflows/docker-ci.yml)  
**Name:** `Docker build & push`  
**Actions:**  
[Docker build & push runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22Docker+build+%26+push%22+branch%3Apart4-monitoring)

What it does:

- Builds the multi-stage Docker image.
- Pushes to GHCR:
  - `ghcr.io/soumya-s-goud/arculus-devops-challenge:<git-sha>`
  - `ghcr.io/soumya-s-goud/arculus-devops-challenge:latest`

GHCR packages UI:  
[GHCR packages for this repo](https://github.com/users/soumya-s-goud/packages?repo=soumya-s-goud%2Farculus-devops-challenge)

---

## 5. Part 3 - Deployment with CD (Kubernetes + Terraform)

We use **kind** as the cluster in CI and for local runs.

### 5.1 Kubernetes manifests (`k8s/`)

- `namespace.yaml`: defines the `orders` namespace.
- `secret-db.yaml`: **example** K8s Secret manifest for DB credentials + `DATABASE_URL`.
  - For demonstration, **dummy credentials** are shown in this file to indicate the schema and key names.
  - Real credentials are **not** taken from this file in CI/CD:
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

- **DB Secret** is created from GitHub Secrets (no real credentials in git).
- **TLS Secret** is created with a short-lived self-signed certificate for `orders.local`.

This:

- Demonstrates TLS termination at the Ingress using a TLS secret.
- Avoids committing TLS material or live DB credentials to the repo.
- Uses **dummy values** in `k8s/secret-db.yaml` purely as a schema reference.

### 5.3 Terraform module (`terraform/`)

**Directory:** [terraform/](./terraform)

Key files:

- `main.tf` - uses `gavinbunney/kubectl`:
  - Creates `Namespace` resource.
  - Applies DB Secret, Postgres Deployment/Service, app Service, and Ingress via `kubectl_manifest`.
- `variables.tf` - `image_tag`, `namespace`.
- `app-deployment.tpl` - templated Deployment (for reference).
- `.terraform.lock.hcl` - provider lock.

### 5.4 CD - direct manifests to kind

**Workflow:** [.github/workflows/deploy-to-kind.yml](./.github/workflows/deploy-to-kind.yml)  
**Name:** `deploy-to-kind`  
**Actions:**  
[deploy-to-kind runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-to-kind%22+branch%3Apart4-monitoring)

What it does (high level):

- Creates a kind cluster.
- Creates Secrets (`orders-db-credentials`, `orders-tls`, `ghcr-pull-secret`).
- Applies `k8s/*.yaml`.
- Waits for Postgres & Orders app rollouts.
- Runs `/health` smoke test from inside the cluster.
- Collects and uploads cluster logs as an artifact.

### 5.5 CD - Terraform-based deployment to kind

**Workflow:** [.github/workflows/deploy-with-terraform.yml](./.github/workflows/deploy-with-terraform.yml)  
**Name:** `deploy-with-terraform`  
**Actions:**  
[deploy-with-terraform runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-with-terraform%22+branch%3Apart4-monitoring)

What it does:

- Creates a kind cluster.
- Installs kubectl and Terraform.
- Creates Secrets (`orders-db-credentials`, `orders-tls`, `ghcr-pull-secret`).
- Runs `terraform init` and `terraform apply` in `terraform/`.
- Applies the Orders app Deployment via `kubectl apply`.
- Waits for rollout; runs `/health` smoke test.
- Collects and uploads cluster logs.

---

## 6. Part 4 - Monitoring & Logging

### 6.1 Monitoring stack: Prometheus + Grafana

**Workflow:** [.github/workflows/monitoring.yml](./.github/workflows/monitoring.yml)  
**Name:** `deploy-monitoring-ci`  
**Actions:**  
[deploy-monitoring-ci runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-monitoring-ci%22+branch%3Apart4-monitoring)

What it does:

- Creates a kind cluster.
- Deploys the Orders stack with manifests and Secrets/TLS.
- Waits for rollouts; runs `/health` smoke test.
- Installs `kube-prometheus-stack` via Helm in `monitoring` namespace.
- Applies [monitoring/alerts-orders.yaml](./monitoring/alerts-orders.yaml) as a PrometheusRule.
- Verifies monitoring pods and services.

### 6.2 Monitoring artifacts: dashboards and alerts

**Directory:** [monitoring/](./monitoring)

- **alerts-orders.yaml**:
  - `PrometheusRule` defining example alerts for:
    - High HTTP 5xx rate on Orders API.
    - High p95 latency.
    - DB connection errors.
  - Applied automatically by `monitoring.yml`.
- **grafana-orders-dashboard.json**:
  - Example Grafana dashboard JSON for Orders API metrics.
  - Can be imported via Grafana UI (“Dashboards → Import”).

### 6.3 Logging

- Deployment workflows gather:
  - Pods and services listing.
  - Orders app logs.
  - Postgres logs.
- These are uploaded as GitHub Actions artifacts (e.g., `deploy-to-kind-logs`, `deploy-with-terraform-logs`).

---

## 7. Part 5 - Security (Optional) & Best Practices

- **Non-root containers**:
  - Dockerfile uses `USER appuser`.
  - `app-deployment.yaml` sets `runAsNonRoot: true`, `runAsUser: 1000`.
- **Resource limits**:
  - App and DB deployments define CPU/memory requests and limits.
- **imagePullSecrets**:
  - `ghcr-pull-secret` created from `GITHUB_TOKEN` in workflows.
- **Secrets**:
  - `k8s/secret-db.yaml` uses **dummy placeholders** to illustrate the Secret schema.
  - Real credentials come from **GitHub Secrets**, used to create `orders-db-credentials` in CI/CD.
- **mTLS**:
  - Not implemented between app and DB.
  - TLS is used at the Ingress via `orders-tls` (self-signed).

---

## 8. Running Locally - Reproducible Steps

(unchanged in structure; now with links above)

- Local app + Postgres.
- kind + manifests.
- kind + Terraform.
- Local monitoring stack with Grafana/Prometheus and importing the dashboard JSON.

For detailed commands see the sections above and the repository itself.

---

## 9. CI/CD Pipelines - Summary & Links

- **CI - build, lint, tests, coverage, .deb:**  
  [.github/workflows/ci.yml](./.github/workflows/ci.yml) - [CI runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22CI+Workflow+-+Build+%26+Test+Debian+Package%22+branch%3Apart4-monitoring)

- **Docker build & push:**  
  [.github/workflows/docker-ci.yml](./.github/workflows/docker-ci.yml) - [Docker CI runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22Docker+build+%26+push%22+branch%3Apart4-monitoring)

- **CD - manifests to kind:**  
  [.github/workflows/deploy-to-kind.yml](./.github/workflows/deploy-to-kind.yml) - [deploy-to-kind runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-to-kind%22+branch%3Apart4-monitoring)

- **CD - Terraform + kubectl:**  
  [.github/workflows/deploy-with-terraform.yml](./.github/workflows/deploy-with-terraform.yml) - [deploy-with-terraform runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-with-terraform%22+branch%3Apart4-monitoring)

- **Monitoring - Prometheus + Grafana:**  
  [.github/workflows/monitoring.yml](./.github/workflows/monitoring.yml) - [deploy-monitoring-ci runs](https://github.com/soumya-s-goud/arculus-devops-challenge/actions?query=workflow%3A%22deploy-monitoring-ci%22+branch%3Apart4-monitoring)

---

## 10. Assumptions, Limitations, and Future Improvements

### Assumptions

- GHCR is accessible from CI kind clusters using `GITHUB_TOKEN` and `ghcr-pull-secret`.
- Dummy credentials in `k8s/secret-db.yaml` are acceptable as examples; real credentials come from GitHub Secrets.
- In-cluster Postgres is acceptable for this challenge.

### Limitations

- No self-hosted runners; all workflows use GitHub-hosted `ubuntu-latest` runners and ephemeral kind clusters.
- HTTPS validation is not automated in CI (smoke tests use HTTP `/health` inside the cluster).
- Monitoring metrics and alerts are illustrative; wiring a full metrics exporter is left as future work.
- mTLS between app and DB is not implemented.

### Future improvements

- Integrate secrets manager (SOPS/SealedSecrets/Vault).
- Add HTTPS smoke tests in CI.
- Expose application metrics endpoint and fully back Prometheus/Grafana panels.
- Implement mTLS for DB connections.
