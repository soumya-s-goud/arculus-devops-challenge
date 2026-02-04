apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-app
  namespace: ${namespace}
  labels:
    app: orders-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: orders-app
  template:
    metadata:
      labels:
        app: orders-app
    spec:
      initContainers:
        - name: init-db
          image: ghcr.io/soumya-s-goud/arculus-devops-challenge:${image_tag}
          imagePullPolicy: IfNotPresent
          env:
            - name: DB_HOST
              value: "postgres"
            - name: DB_PORT
              value: "5432"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: POSTGRES_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: POSTGRES_PASSWORD
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: POSTGRES_DB
          command:
            - sh
            - -c
            - |
              set -euo pipefail
              echo "Init container: waiting for Postgres and creating tables"
              python - <<'PY'
              import time, sys
              from sqlalchemy import create_engine
              from sqlalchemy.exc import OperationalError
              from apps.main import app, db
              host = os.environ.get("DB_HOST","postgres")
              port = os.environ.get("DB_PORT","5432")
              user = os.environ.get("DB_USER")
              pw = os.environ.get("DB_PASSWORD")
              name = os.environ.get("DB_NAME")
              # Build SQLAlchemy URL the app expects if DATABASE_URL not used
              conn = f"postgresql://{user}:{pw}@{host}:{port}/{name}"
              for i in range(1,31):
                  try:
                      with app.app_context():
                          db.create_all()
                      print("DB schema ensured")
                      break
                  except Exception as e:
                      print(f"DB create_all attempt {i} failed: {e}", file=sys.stderr)
                      time.sleep(2)
              else:
                  print("Failed to initialize DB after retries", file=sys.stderr)
                  sys.exit(1)
              PY
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
      containers:
        - name: orders
          image: ghcr.io/soumya-s-goud/arculus-devops-challenge:${image_tag}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8000
              name: http
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: DATABASE_URL
            - name: DB_HOST
              value: "postgres"
            - name: DB_PORT
              value: "5432"
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: POSTGRES_USER
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: POSTGRES_PASSWORD
            - name: DB_NAME
              valueFrom:
                secretKeyRef:
                  name: orders-db-credentials
                  key: POSTGRES_DB
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "250m"
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 2
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 2
          securityContext:
            runAsUser: 1000
            runAsNonRoot: true