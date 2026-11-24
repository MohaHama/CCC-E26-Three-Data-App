
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = "cloud-computing-continuum-14"
  region  = "europe-west1"
}

resource "google_compute_network" "frontend" {
  name                    = "vpc-frontend"
  auto_create_subnetworks = false
}

resource "google_compute_network" "backend" {
  name                    = "vpc-backend"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "frontend" {
  name          = "subnet-frontend"
  region        = "europe-west1"
  ip_cidr_range = "10.10.1.0/24"
  network       = google_compute_network.frontend.id
}

resource "google_compute_subnetwork" "backend" {
  name          = "subnet-backend"
  region        = "europe-west1"
  ip_cidr_range = "10.20.1.0/24"
  network       = google_compute_network.backend.id
}

resource "google_sql_database_instance" "database" {
  depends_on = [google_service_networking_connection.private_connection]

  name             = "ccc-database"
  region           = "europe-west10"
  database_version = "MYSQL_8_4"

  deletion_protection = true

  lifecycle {
    ignore_changes = [
      settings
    ]
  }

  settings {
    tier              = "db-perf-optimized-N-8"
    edition           = "ENTERPRISE_PLUS"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 100
    disk_autoresize   = false

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.backend.id
    }
  }
}

resource "google_vpc_access_connector" "backend" {
  name          = "vpc-connector-backend"
  region        = "europe-west1"
  network       = google_compute_network.backend.name
  ip_cidr_range = "10.20.2.0/28"

  min_instances = 2
  max_instances = 10
  machine_type  = "e2-micro"
}

resource "google_cloud_run_v2_service" "backend" {
  name     = "three-data-backend"
  location = "europe-west1"
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = true

  lifecycle {
    ignore_changes = [
      client,
      invoker_iam_disabled,
      template
    ]
  }

  template {
    containers {
      image = "europe-north2-docker.pkg.dev/cloud-computing-continuum-14/ccc-backend/three-data-backend@sha256:c5803e16b17579bff9a0540b8655624eb34829d07f686cfab9fdb6e21ce694e6"

      ports {
        container_port = 8080
      }

      env {
        name  = "DB_NAME"
        value = "ccc-database"
      }

      env {
        name  = "DB_USER"
        value = "ccc-user"
      }

      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = "cloud-computing-continuum-14:europe-west10:ccc-database"
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.backend.id
      egress    = "ALL_TRAFFIC"
    }
  }
}

resource "google_cloud_run_v2_service" "frontend" {
  name     = "three-data-frontend"
  location = "europe-west1"
  ingress  = "INGRESS_TRAFFIC_ALL"

  deletion_protection = true

  lifecycle {
    ignore_changes = [
      client,
      invoker_iam_disabled,
      template
    ]
  }

  template {
    containers {
      image = "europe-west3-docker.pkg.dev/cloud-computing-continuum-14/my-docker-repo/frontend-app@sha256:368b001b102cc8cc208d8f903b1d7e76155859417e69e5e681768e871ab7b5d7"

      ports {
        container_port = 8080
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.frontend.id
      egress    = "ALL_TRAFFIC"
    }
  }
}

resource "google_vpc_access_connector" "frontend" {
  name          = "vpc-connector-frontend"
  region        = "europe-west1"
  network       = google_compute_network.frontend.name
  ip_cidr_range = "10.10.2.0/28"

  min_instances = 2
  max_instances = 10
  machine_type  = "e2-micro"
}

resource "google_compute_network_peering" "backend_to_frontend" {
  name         = "peer-backend-to-frontend"
  network      = google_compute_network.backend.self_link
  peer_network = google_compute_network.frontend.self_link
}

resource "google_compute_network_peering" "frontend_to_backend" {
  name         = "peer-frontend-to-backend"
  network      = google_compute_network.frontend.self_link
  peer_network = google_compute_network.backend.self_link
}

resource "google_compute_global_address" "private_ip_range" {
  name          = "vpc-backend-ip-range-1793481024940"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.134.176.0"
  prefix_length = 20
  network       = google_compute_network.backend.id
}

resource "google_service_networking_connection" "private_connection" {
  network = google_compute_network.backend.id
  service = "servicenetworking.googleapis.com"

  reserved_peering_ranges = [
    google_compute_global_address.private_ip_range.name
  ]
}
