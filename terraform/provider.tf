terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.8.0"
    }
  }
}


provider "google" {
  region      = "us-west1"
  project     = "ardent-bridge-324620"
  credentials = file("ardent-bridge-324620-3b887235fff3.json")
  zone        = "us-west1-a"

}