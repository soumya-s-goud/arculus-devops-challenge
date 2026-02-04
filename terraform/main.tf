terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.17.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "kubectl" {
  # uses default kubeconfig (~/.kube/config) or KUBECONFIG env var
}

locals {
  # Namespace manifest (ensures namespace is created first)
  namespace_manifest = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
    }
  })

  # Load YAML files from ../k8s (strings). These files include "namespace: orders" which will be replaced below.
  secret_db_raw       = file("${path.module}/../k8s/secret-db.yaml")
  postgres_deploy_raw = file("${path.module}/../k8s/postgres-deployment.yaml")
  postgres_svc_raw    = file("${path.module}/../k8s/postgres-service.yaml")
  app_service_raw     = file("${path.module}/../k8s/app-service.yaml")
  ingress_raw         = file("${path.module}/../k8s/ingress.yaml")

  # Replace hardcoded namespace text "namespace: orders" with the chosen namespace variable.
  secret_db        = replace(local.secret_db_raw, "namespace: orders", "namespace: ${var.namespace}")
  postgres_deploy  = replace(local.postgres_deploy_raw, "namespace: orders", "namespace: ${var.namespace}")
  postgres_svc     = replace(local.postgres_svc_raw, "namespace: orders", "namespace: ${var.namespace}")
  app_service      = replace(local.app_service_raw, "namespace: orders", "namespace: ${var.namespace}")
  ingress          = replace(local.ingress_raw, "namespace: orders", "namespace: ${var.namespace}")

  # Render the app deployment from the template so we can substitute image_tag and namespace
  app_deploy = templatefile("${path.module}/app-deployment.tpl", {
    image_tag = var.image_tag
    namespace = var.namespace
  })

  # Manifests to apply after namespace exists
  manifests = {
    "orders-db-secret" = local.secret_db
    "postgres-deployment" = local.postgres_deploy
    "postgres-service" = local.postgres_svc
    "app-deployment" = local.app_deploy
    "app-service" = local.app_service
    "ingress" = local.ingress
  }
}

# Create namespace first
resource "kubectl_manifest" "namespace" {
  yaml_body = local.namespace_manifest
}

# Apply other manifests (depends on namespace)
resource "kubectl_manifest" "apply" {
  for_each = local.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.namespace]
}