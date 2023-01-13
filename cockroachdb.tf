data "google_client_config" "default" {}

provider "kubernetes" {
  host = "https://${google_container_cluster.gcc.endpoint}"

  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gcc.master_auth[0].cluster_ca_certificate)
}

variable "dbserver" {
  description = "name of the database server"
  default     = "cockroachdb"
}

resource "kubernetes_namespace" "kn" {
  metadata {
    name = var.dbserver
  }
}

resource "kubernetes_secret" "ks-client-root" {
  metadata {
    name      = "${var.dbserver}.client.root"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app : var.dbserver
    }
  }

  data = {
    "ca.crt"          = "${file("${path.module}/certs/ca.crt")}"
    "client.root.crt" = "${file("${path.module}/certs/client.root.crt")}"
    "client.root.key" = "${file("${path.module}/certs/client.root.key")}"

  }
  binary_data = {
    "client.root.pk8" = "${filebase64("${path.module}/certs/client.root.pk8")}"
  }
}

resource "kubernetes_secret" "ks-node" {
  metadata {
    name      = "${var.dbserver}.node"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app : var.dbserver
    }
  }

  data = {
    "ca.crt"          = "${file("${path.module}/certs/ca.crt")}"
    "client.root.crt" = "${file("${path.module}/certs/client.root.crt")}"
    "client.root.key" = "${file("${path.module}/certs/client.root.key")}"
    "node.crt"        = "${file("${path.module}/certs/node.crt")}"
    "node.key"        = "${file("${path.module}/certs/node.key")}"
  }
}

resource "kubernetes_service_account" "ksa" {
  metadata {
    name      = var.dbserver
    namespace = kubernetes_namespace.kn.id
    labels = {
      app : var.dbserver
    }
  }
}

resource "kubernetes_role" "kr" {
  metadata {
    name      = var.dbserver
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.dbserver
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "krb" {
  metadata {
    name      = var.dbserver
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.dbserver
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = var.dbserver
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.dbserver
    namespace = kubernetes_namespace.kn.id
  }
}

resource "kubernetes_stateful_set" "kss" {
  metadata {
    name      = var.dbserver
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.dbserver
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        app = var.dbserver
      }
    }
    service_name = var.dbserver
    template {
      metadata {
        labels = {
          app = var.dbserver
        }
      }

      spec {
        service_account_name = var.dbserver

        affinity {
          pod_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = [var.dbserver]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        container {
          name              = var.dbserver
          image             = "${var.dbserver}/cockroach:v22.1.9"
          image_pull_policy = "IfNotPresent"

          resources {
            requests = {
              cpu    = "2"
              memory = "8Gi"
            }
            limits = {
              cpu    = "2"
              memory = "8Gi"
            }
          }

          port {
            container_port = 26257
            name           = "grpc"
          }

          port {
            container_port = 8080
            name           = "http"
          }

          /* readiness_probe {
            http_get {
              path   = "/health?ready=1"
              port   = "http"
              scheme = "HTTPS"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 2
          } */

          volume_mount {
            name       = "datadir"
            mount_path = "/cockroach/cockroach-data"
          }

          volume_mount {
            name       = "certs"
            mount_path = "/cockroach/cockroach-certs"
          }

          env {
            name  = "COCKROACH_CHANNEL"
            value = "kubernetes-secure"
          }

          env {
            name = "GOMAXPROCS"
            value_from {
              resource_field_ref {
                resource = "limits.cpu"
                divisor  = "1"
              }
            }
          }

          env {
            name = "MEMORY_LIMIT_MIB"
            value_from {
              resource_field_ref {
                resource = "limits.memory"
                divisor  = "1Mi"
              }
            }
          }

          command = [
            "/bin/bash",
            "-ecx",
            "exec /cockroach/cockroach start --log=\"sinks: {stderr: {channels: [ALL]}}\" --certs-dir /cockroach/cockroach-certs --advertise-addr $(hostname -f) --http-addr 0.0.0.0 --join cockroachdb-0.cockroachdb.cockroachdb.svc.cluster.local,cockroachdb-1.cockroachdb.cockroachdb.svc.cluster.local,cockroachdb-2.cockroachdb.cockroachdb.svc.cluster.local --cache $(expr $MEMORY_LIMIT_MIB / 4)MiB --max-sql-memory $(expr $MEMORY_LIMIT_MIB / 4)MiB"
          ]
        }

        termination_grace_period_seconds = 60
        volume {
          name = "datadir"
          persistent_volume_claim {
            claim_name = "datadir"
          }
        }

        volume {
          name = "certs"
          secret {
            secret_name  = "${var.dbserver}.node"
            default_mode = "0400"
          }
        }
      }
    }
    pod_management_policy = "Parallel"
    update_strategy {
      type = "RollingUpdate"
    }

    volume_claim_template {
      metadata {
        name = "datadir"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "16Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ks-public" {
  metadata {
    name      = "${var.dbserver}-public"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.dbserver
    }
  }
  spec {
    selector = {
      app = kubernetes_stateful_set.kss.spec.0.template.0.metadata[0].labels.app
    }
    port {
      name        = "grpc"
      port        = 26257
      target_port = 26257
    }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_service" "ks" {
  metadata {
    /* This service only exists to create DNS entries for each pod in the stateful
    set such that they can resolve each other's IP addresses. It does not
    create a load-balanced ClusterIP and should not be used directly by clients
    in most circumstances. */
    name      = var.dbserver
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.dbserver
    }
    annotations = {
      "service.alpha.kubernetes.io/tolerate-unready-endpoints" = "true"
      "prometheus.io/scrape"                                   = "true"
      "prometheus.io/path"                                     = "_status/vars"
      "prometheus.io/port"                                     = "8080"
    }
  }
  spec {
    port {
      name        = "grpc"
      port        = 26257
      target_port = 26257
    }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }

    publish_not_ready_addresses = true
    cluster_ip                  = "None"
    selector = {
      app = kubernetes_stateful_set.kss.spec.0.template.0.metadata[0].labels.app
    }
  }
}

resource "kubernetes_pod_disruption_budget" "kpdb" {
  metadata {
    name      = "${var.dbserver}-budget"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = var.dbserver
    }
  }
  spec {
    max_unavailable = "1"
    selector {
      match_labels = {
        app = kubernetes_stateful_set.kss.spec.0.template.0.metadata[0].labels.app
      }
    }
  }
}

output "lb_ip" {
  value = kubernetes_service.ks-public.status.0.load_balancer.0.ingress.0.ip
} 