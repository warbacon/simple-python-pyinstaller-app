# Entregable 3 - Virtualización de Sistemas

_Realizado por Joaquín Guerra Tocino._

## Enunciado

- La base del ejercicio es la misma que la vista en clase para la aplicación de
React. La diferencia es que en este caso se trata de una aplicación Python.

- Por tanto, usaremos Jenkins desplegado en un contenedor Docker y un agente
Docker in Docker para ejecutar el pipeline.

- Debéis crear un pipeline en Jenkins que realice el despliegue de la
aplicación en un contenedor Docker.

- El despliegue de los dos contenedores Docker necesarios (Docker in Docker y
Jenkins) debe realizarse mediante Terraform. Para crear la imagen personalizada
de Jenkins debéis usar un Dockerfile tal como hemos visto en clase, esto no
tiene que realizarse mediante Terraform.

- El despliegue desde el pipeline debe hacerse usando una rama llamada main.

## Respuesta

Tal y como nos pide el ejercicio, he creado un fork del repositorio que se
menciona en el enunciado de la práctica:
<https://github.com/warbacon/simple-python-pyinstaller-app>

Una vez hecho esto, como la rama por defecto del repositorio era master y nos
pide que hagamos el pipeline usando la rama main, simplemente he renombrado la
rama `master` a `main` desde el propio GitHub. Una vez hecho esto, he clonado
el repositorio en mi máquina.

Dentro del repositorio he creado el directorio `docs`, donde se encontraran los
ficheros pedidos para completar el entregable. Tenemos un `Dockefile` ya
proporcionado por la práctica de Jenkins para crear una imagen personalizada
del mismo, el Jenkinsfile que nos proporciona el enunciado para hacer el
pipeline y la configuración de Terraform para iniciar los dos contenedores.

El ejercicio no pide que creemos la imagen personalizada de docker usando
Terraform, pero yo lo he añadido a la configuración porque es bastante sencillo
de implementar. Echemosle un vistazo a la configuración de Terraform paso por paso:

```terraform
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}
```

En primer especificamos que usaremos docker para la configuración. Esto es
necesario para que a la hora de ejecutar `terraform init`, se nos instale el
proveedor automáticamente.

En el resto de la configuración, estaremos simplemente traduciendo el comando dado
en la práctica de Jenkins a la configuración de Terraform.

```terraform
resource "docker_network" "jenkins_network" {
  name = "jenkins"
}
```

Creamos la red que usaran el contenedor de DinD y el de Jenkins para comunicarse.

```terraform
resource "docker_volume" "jenkins_docker_certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}
```

Los dos volúmenes necesitados por Jenkins.

```terraform
resource "docker_image" "jenkins_blueocean" {
  name = "myjenkins-blueocean"
  build {
    context = "."
  }
}
```

Aquí estamos creando un recurso para la imagen personalizada de Jenkins. Se
leera cualquier Dockerfile que se encuntre en el mismo directorio que en el
archivo de configuración de Terraform.

Y ahora los dos contenedores:

```terraform
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
```

En primer lugar tenemos el contenedor de DinD. Está directamente traducido de este comando:

```sh
docker run --name jenkins-docker --rm --detach \
  --privileged --network jenkins --network-alias docker \
  --env DOCKER_TLS_CERTDIR=/certs \
  --volume jenkins-docker-certs:/certs/client \
  --volume jenkins-data:/var/jenkins_home \
  --publish 2376:2376 \
  docker:dind --storage-driver overlay2
```

Estamos usando los volúmenes especificados arriba para que los datos persistan
aunque se elimine el contenedor, y también estamos usando la red llamada
`jenkins`, a la que le establecemos un alias de `docker` y exponemos el puerto
2376 para que pueda ser usada por el contenedor de Jenkins a la hora de
completar el pipeline.

```terraform
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
```

Y por último tenemos el contenedor de Jenkins con su imagen personalizada. Todo
traducido de este comando:

```sh
docker run --name jenkins-blueocean --restart=on-failure --detach \
  --network jenkins --env DOCKER_HOST=tcp://docker:2376 \
  --env DOCKER_CERT_PATH=/certs/client --env DOCKER_TLS_VERIFY=1 \
  --publish 8080:8080 --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  myjenkins-blueocean
```

Lo único a resaltar es que estamos haciendo que este recurso dependa de que el
contenedor de DinD esté activo.

Aquí está el fichero de configuración completo:

```terraform
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins"
}

resource "docker_volume" "jenkins_docker_certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}

resource "docker_image" "jenkins_blueocean" {
  name = "myjenkins-blueocean"
  build {
    context = "."
  }
}

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
```

### Configuración del pipeline y despliegue

Para relizar el despliegue de la aplicación, primero deberemos levantar los
contenedores con Terraform. Para ello, primero ejecutaremos `terraform init`
para que se creen los archivos necesarios para empezar el despliegue de los
contenedores y luego `terraform apply` para aplicar la configuración.

Una vez hecho esto, abriremos el navegador e introduciremos la siguiente url:
<https://localhost:8080>. Nos aparecerá el panel de configuración de Jenkins.
Deberemos de registranos y configurar los plugins que necesitemos.

Una vez dentro de Jenkins, crearemos un nuevo pipeline con la opción _Pipeline
Script from SCM_. Aquí seleccionaremos como repositorio este mismo repositorio,
las ramas a construir serán `*/main` y el _Script Path_ será
`docs/Jenkinsfile`.

Una vez creado el pipeline, le daremos a _Construir ahora_ y el pipeline se
ejecutará correctamente si hemos seguido todos los pasos adecuadamente.
