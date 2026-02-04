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
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 2
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 2
          securityContext:
            runAsUser: 1000
            runAsNonRoot: true