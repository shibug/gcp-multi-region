variable "pgdb" {
  description = "name of the database server"
  default     = "postgres"
}

resource "kubernetes_namespace" "kn-pg" {
  metadata {
    name = var.pgdb
  }
}

/* resource "kubernetes_secret" "ks-pg" {
  metadata {
    name      = "${var.pgdb}.secret"
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app : var.pgdb
    }
  }

  data = {
    "postgres-passwd" = "postgres"
  }
} */

resource "kubernetes_service_account" "ksa-pg" {
  metadata {
    name      = var.pgdb
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app : var.pgdb
    }
  }
}

resource "kubernetes_role" "kr-pg" {
  metadata {
    name      = var.pgdb
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app = var.pgdb
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get"]
  }
}

resource "kubernetes_role_binding" "krb-pg" {
  metadata {
    name      = var.pgdb
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app = var.pgdb
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = var.pgdb
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.pgdb
    namespace = kubernetes_namespace.kn-pg.id
  }
}

resource "kubernetes_stateful_set" "kss-pg" {
  metadata {
    name      = var.pgdb
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app = var.pgdb
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = var.pgdb
      }
    }
    service_name = var.pgdb
    template {
      metadata {
        labels = {
          app = var.pgdb
        }
      }

      spec {
        service_account_name = var.pgdb

        affinity {
          pod_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = [var.pgdb]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        container {
          name              = var.pgdb
          image             = "${var.pgdb}:15.1"
          image_pull_policy = "IfNotPresent"

          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {
              cpu    = "1"
              memory = "2Gi"
            }
          }

          port {
            container_port = 5432
            name           = "tcp"
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          /*  volume_mount {
            name       = "secrets"
            mount_path = "/run/secrets"
          } */

          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }

          /* env {
            name  = "POSTGRES_PASSWORD_FILE"
            value = "/run/secrets/postgres-passwd"
          } */

          env {
            name  = "POSTGRES_PASSWORD"
            value = "postgres"
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

        }

        termination_grace_period_seconds = 60
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = "data"
          }
        }

        /* volume {
          name = "secrets"
          secret {
            secret_name  = "${var.pgdb}.secret"
            default_mode = "0400"
          }
        } */
      }
    }
    pod_management_policy = "Parallel"
    update_strategy {
      type = "RollingUpdate"
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "4Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ks-public-pg" {
  metadata {
    name      = "${var.pgdb}-public"
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app = var.pgdb
    }
  }
  spec {
    selector = {
      app = kubernetes_stateful_set.kss-pg.spec.0.template.0.metadata[0].labels.app
    }
    port {
      name        = "tcp"
      port        = 5432
      target_port = 5432
    }

    type = "LoadBalancer"
  }
}

resource "kubernetes_service" "ks-pg" {
  metadata {
    /* This service only exists to create DNS entries for each pod in the stateful
    set such that they can resolve each other's IP addresses. It does not
    create a load-balanced ClusterIP and should not be used directly by clients
    in most circumstances. */
    name      = var.pgdb
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app = var.pgdb
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
      name        = "tcp"
      port        = 5432
      target_port = 5432
    }

    publish_not_ready_addresses = true
    cluster_ip                  = "None"
    selector = {
      app = kubernetes_stateful_set.kss-pg.spec.0.template.0.metadata[0].labels.app
    }
  }
}

resource "kubernetes_pod_disruption_budget" "kpdb-pg" {
  metadata {
    name      = "${var.pgdb}-budget"
    namespace = kubernetes_namespace.kn-pg.id
    labels = {
      app = var.pgdb
    }
  }
  spec {
    max_unavailable = "1"
    selector {
      match_labels = {
        app = kubernetes_stateful_set.kss-pg.spec.0.template.0.metadata[0].labels.app
      }
    }
  }
}

output "postgres_lb_ip" {
  value = kubernetes_service.ks-public.status.0.load_balancer.0.ingress.0.ip
} 