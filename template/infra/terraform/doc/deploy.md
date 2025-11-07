# Despliegue de Aplicación Flutter con API REST en Google Cloud

Este documento describe la arquitectura y el proceso de despliegue de una aplicación Flutter (Android) que consume una API RESTful (Dart/Shelf) con una base de datos PostgreSQL en Google Cloud Platform.

## 1. Arquitectura de la Solución

La arquitectura propuesta es escalable, segura y completamente administrada, utilizando los siguientes componentes clave de Google Cloud:

*   **Global Load Balancer (Frontend & Backend):**
    *   **Función:** Actúa como el punto de entrada público para tu API, gestionando tu dominio personalizado (`miapp.miempresa.com`) y proporcionando HTTPS con certificados SSL administrados. El frontend recibe las solicitudes y el backend las enruta inteligentemente a tu servicio de Cloud Run, especialmente las rutas bajo `/api/*`.
*   **Cloud Run Service (`cloud-run-api`):**
    *   **Función:** Aloja tu API REST desarrollada en Dart/Shelf. Es un servicio serverless que escala automáticamente de cero a miles de instancias según la demanda, y está configurado para acceso público.
*   **Cloud SQL for PostgreSQL (`postgresql-db`):**
    *   **Función:** Proporciona una instancia de base de datos PostgreSQL 16 completamente administrada. Google Cloud se encarga de la infraestructura, copias de seguridad, parches y alta disponibilidad.
*   **Secret Manager (`db-credentials`):**
    *   **Función:** Almacena de forma segura las credenciales sensibles (ej. contraseña) para que tu servicio de Cloud Run se conecte a la base de datos PostgreSQL, evitando que estén expuestas en el código.

## 2. Proceso de Despliegue

El despliegue de esta arquitectura se realiza principalmente a través de Terraform, con pasos adicionales para tu código y datos.

### 2.1. Despliegue de la Infraestructura con Terraform

1.  **Generar Configuración de Terraform:** Utiliza la interfaz de App Design Center para "Ver y descargar la configuración de Terraform" de tu diseño.
2.  **Inicializar Terraform:** En tu terminal (local o Cloud Shell), navega al directorio de Terraform y ejecuta `terraform init`.
3.  **Planificar Despliegue:** Revisa los cambios propuestos con `terraform plan`.
4.  **Aplicar Despliegue:** Ejecuta `terraform apply` y confirma con `yes` para provisionar los recursos en tu proyecto de GCP (`cacsi-451017`).

### 2.2. Despliegue del Código de tu API (Dart/Shelf) en Cloud Run

Cloud Run despliega imágenes de Docker. Tu configuración actual de Docker Compose para desarrollo es un buen punto de partida.

1.  **Containerizar tu API:** Asegúrate de tener un `Dockerfile` en tu proyecto Dart/Shelf que empaquete tu aplicación.
2.  **Construir y Subir Imagen Docker:**
    *   Autentica Docker con GCP: `gcloud auth configure-docker`
    *   Construye tu imagen: `docker build -t gcr.io/cacsi-451017/dart-shelf-app:latest .`
    *   Sube la imagen a Google Container Registry: `docker push gcr.io/cacsi-451017/dart-shelf-app:latest`
3.  **Despliegue en Cloud Run:** El `terraform apply` configurará Cloud Run para usar esta imagen. Para futuras actualizaciones, repite los pasos de construcción y subida de la imagen.

### 2.3. Configuración de la Base de Datos PostgreSQL

Cloud SQL for PostgreSQL es un servicio administrado, por lo que no desplegarás un contenedor Docker de PostgreSQL directamente.

1.  **Conexión a Cloud SQL:** Una vez que Terraform haya provisionado la instancia, conéctate a ella. La forma más segura es usar `gcloud sql connect postgresql-db --user=postgres` desde Cloud Shell, o el Cloud SQL Auth Proxy desde tu máquina local.
2.  **Aplicar Esquema y Datos Semilla:**
    *   **`pgschema`:** Puedes usar tu herramienta `pgschema` para aplicar el esquema de tu base de datos a la instancia de Cloud SQL. `pgschema` es totalmente compatible con Cloud SQL for PostgreSQL.
    *   **Scripts SQL:** Alternativamente, puedes ejecutar tus scripts SQL (`CREATE TABLE`, `INSERT`, etc.) directamente a través de la conexión `psql`.

### 2.4. Pasos Post-Despliegue

1.  **Configuración DNS:** Una vez que el Global Load Balancer esté activo y tenga una IP externa, actualiza los registros DNS de tu dominio (`miempresa.com`) para que `miapp.miempresa.com` apunte a esa IP.
2.  **Actualizar Credenciales de DB:** Reemplaza el placeholder `"your-db-password"` en Secret Manager (`db-credentials`) con una contraseña segura y real para tu base de datos.
