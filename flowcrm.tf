variable "frontend" {
  description = "name of the the frontend"
  default     = "flowcrm"
}

resource "kubernetes_service_account" "frontend_ksa" {
  metadata {
    name      = var.frontend
    namespace = kubernetes_namespace.kn.id
    labels = {
      app : var.frontend
    }
  }
}

resource "kubernetes_role_binding" "frontend_krb" {
  metadata {
    name      = var.frontend
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.frontend
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = var.dbserver
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.frontend
    namespace = kubernetes_namespace.kn.id
  }
}

resource "kubernetes_deployment" "frontend_kd" {

  metadata {
    name      = var.frontend
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.frontend
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = var.frontend
      }
    }

    template {
      metadata {
        labels = {
          app = var.frontend
        }
      }

      spec {
        service_account_name = var.frontend

        container {
          name  = var.frontend
          image = "shibug/flowcrm:1.0.1"

          env {
            name  = "DB_URL"
            value = "jdbc:postgresql://35.188.174.202:26257/flowcrm?sslmode=verify-ca&sslcert=certs/client.root.crt&sslkey=certs/client.root.pk8&sslrootcert=certs/ca.crt"
          }
          env {
            name  = "DB_USER"
            value = "root"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          volume_mount {
            name       = "certs"
            mount_path = "/certs"
          }

          resources {
            limits = {
              cpu    = "1"
              memory = "512Mi"
            }
            requests = {
              cpu    = "0.5"
              memory = "512Mi"
            }
          }

          /* readiness_probe {
            http_get {
              path   = "/login"
              port   = 8080
              scheme = "HTTPS"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 2
          } */
        }

        volume {
          name = "certs"
          secret {
            secret_name  = "${var.dbserver}.client.root"
            default_mode = "0400"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "frontend_ks_public" {
  metadata {
    name      = "${var.frontend}-public"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.frontend
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.frontend_kd.spec.0.template.0.metadata[0].labels.app
    }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

output "frontend_lb_ip" {
  value = kubernetes_service.frontend_ks_public.status.0.load_balancer.0.ingress.0.ip
} 