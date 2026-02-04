variable "image_tag" {
  description = "Image tag for the orders app (e.g. sha-0b3e0e9 or latest)"
  type        = string
  default     = "sha-0b3e0e9"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy into"
  type        = string
  default     = "orders"
}