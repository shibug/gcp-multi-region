data "google_client_config" "default" {}

provider "kubernetes" {
  host = "https://${google_container_cluster.gcc.endpoint}"

  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gcc.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "kn" {
  metadata {
    name = "cockroachdb"
  }
}
resource "kubernetes_service_account" "ksa" {
  metadata {
    name = "cockroachdb"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app: "cockroachdb"
    }
  }
}
resource "kubernetes_role" "kr" {
  metadata {
    name = "cockroachdb"
    namespace = kubernetes_namespace.kn.id
    labels = {
      app = "cockroachdb"
    }
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    verbs          = ["get"]
  }
}

#------------------
resource "kubernetes_deployment" "kd" {
  metadata {
    name      = "hello-server"
    namespace = kubernetes_namespace.kn.id
    labels = {
      test = "hello-server"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        test = "hello-server"
      }
    }

    template {
      metadata {
        labels = {
          test = "hello-server"
        }
      }

      spec {
        container {
          image = "us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0"
          name  = "hello-server"
        }
      }
    }
  }
}

resource "kubernetes_service" "ks" {
  metadata {
    name      = "hello-server"
    namespace = kubernetes_namespace.kn.id
  }
  spec {
    selector = {
      test = kubernetes_deployment.kd.spec.0.template.0.metadata[0].labels.test
    }
    port {
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

output "lb_ip" {
  value = kubernetes_service.ks.status.0.load_balancer.0.ingress.0.ip
}