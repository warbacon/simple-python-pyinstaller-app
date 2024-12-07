# Configurar el proveedor de Docker
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

# Crear la red de Jenkins
resource "docker_network" "jenkins_network" {
  name = "jenkins"
}

# Crear los volúmenes
resource "docker_volume" "jenkins_docker_certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}

# Construir la imagen personalizada de Jenkins
resource "docker_image" "jenkins_blueocean" {
  name = "myjenkins-blueocean"
  build {
    context = "."
  }
}

# Crear el contenedor Docker-in-Docker de Jenkins
resource "docker_container" "jenkins_docker" {
  name       = "jenkins-docker"
  image      = "docker:dind"
  rm         = true
  privileged = true

  networks_advanced {
    name    = docker_network.jenkins_network.name
    aliases = ["docker"]
  }

  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

  volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  ports {
    internal = 2376
    external = 2376
  }

  command = ["--storage-driver", "overlay2"]
}

# Crear el contenedor de Jenkins
resource "docker_container" "jenkins_blueocean" {
  name    = "jenkins-blueocean"
  image   = docker_image.jenkins_blueocean.image_id
  restart = "on-failure"

  networks_advanced {
    name = docker_network.jenkins_network.name
  }

  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1"
  ]

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
    read_only      = true
  }

  depends_on = [docker_container.jenkins_docker]
}
