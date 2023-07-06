module "vpc" {
    source  = "terraform-google-modules/network/google//modules/subnets"
    version = "~> 2.0.0"

    project_id   = "ardent-bridge-324620"
    network_name = "Interview-vpc"

    subnets = [
        {
            subnet_name           = "subnet-02"
            subnet_ip             = "10.10.20.0/24"
            subnet_region         = "us-west1"
            subnet_private_access = "true"
            subnet_flow_logs      = "true"
            description           = "This subnet has a description"
            purpose               = "INTERNAL_HTTPS_LOAD_BALANCER"
            role                  = "ACTIVE"
        },
        {
            subnet_name                  = "subnet-03"
            subnet_ip                    = "10.10.30.0/24"
            subnet_region                = "us-west1"
            subnet_flow_logs             = "true"
            subnet_flow_logs_interval    = "INTERVAL_10_MIN"
            subnet_flow_logs_sampling    = 0.7
            subnet_flow_logs_metadata    = "INCLUDE_ALL_METADATA"
            subnet_flow_logs_filter_expr = "true"
        }
    ]

    secondary_ranges = {
        subnet-01 = [
            {
                range_name    = "subnet-01-secondary-01"
                ip_cidr_range = "192.168.64.0/24"
            },
        ]

        subnet-02 = []
    }
}


resource "google_container_cluster" "primary" {
  name                     = "my-gke-cluster"
  location                 = "us-west1-a"
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet.name
  remove_default_node_pool = true                ## create the smallest possible default node pool and immediately delete it.
  # networking_mode          = "VPC_NATIVE" 
  initial_node_count       = 1
  
  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes   = true 
    master_ipv4_cidr_block = "10.13.0.0/28"
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.11.0.0/21"
    services_ipv4_cidr_block = "10.12.0.0/21"
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.7/32"
      display_name = "net1"
    }

  }
}

# Create managed node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = "us-west1-a"
  cluster    = google_container_cluster.primary.name
  node_count = 3

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = "dev"
    }

    machine_type = "n1-standard-1"
    preemptible  = true
    #service_account = google_service_account.mysa.email

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}



## Create jump host . We will allow this jump host to access GKE cluster. the ip of this jump host is already authorized to allowin the GKE cluster

resource "google_compute_address" "my_internal_ip_addr" {
  project      = "ardent-bridge-324620"
  address_type = "INTERNAL"
  region       = "us-west1"
  subnetwork   = "subnet1"
  name         = "my-ip"
  address      = "10.0.0.7"
  description  = "An internal IP address for my jump host"
}

resource "google_compute_instance" "default" {
  project      = "ardent-bridge-324620"
  zone         = "us-west1-a"
  name         = "jump-host"
  machine_type = "e2-medium"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = "vpc1"
    subnetwork = "subnet1" # Replace with a reference or self link to your subnet, in quotes
    network_ip         = google_compute_address.my_internal_ip_addr.address
  }

}


## Creare Firewall to access jump hist via iap


resource "google_compute_firewall" "rules" {
  project = "ardent-bridge-324620"
  name    = "allow-ssh"
  network = "vpc1" # Replace with a reference or self link to your network, in quotes

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}



## Create IAP SSH permissions for your test instance

resource "google_project_iam_member" "project" {
  project = "ardent-bridge-324620"
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:terraform-demo-aft@ardent-bridge-324620.iam.gserviceaccount.com"
}

# create cloud router for nat gateway
resource "google_compute_router" "router" {
  project = "ardent-bridge-324620"
  name    = "nat-router"
  network = "vpc1"
  region  = "us-west1"
}

## Create Nat Gateway with module

module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = "ardent-bridge-324620"
  region     = "us-west1"
  router     = google_compute_router.router.name
  name       = "nat-config"

}


############Output############################################
output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}