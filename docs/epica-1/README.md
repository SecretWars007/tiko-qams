# Épica 1: Infraestructura Base y Entorno de Servicios

> **Versión / Tag Oficial:** `epica-1-v1.0`  
> **Estado:** Cerrada y Verificada  
> **Hito:** INFRA completa en Docker Compose, parametrización con variables de entorno, balanceo de carga, persistencia y backups automatizados.

---

## 1. Descripción General
La **Épica 1** establece los cimientos de infraestructura del sistema **Tiko QAMS (Quality Assurance Management System)**. Provee un entorno de desarrollo y pruebas contenerizado mediante **Docker Compose**, asegurando:
* Aislamiento total de dependencias.
* Balanceo de carga y alta disponibilidad para microservicios backend.
* Enrutamiento seguro bajo HTTPS con certificados SSL locales y redirección automática 301.
* Parametrización modular mediante variables de entorno (`.env`).
* Persistencia transaccional de datos y memoria caché.
* Respaldos automáticos programados con rotación de retención (7 días).
* Auditoría centralizada de eventos (Seq) y simulación de correo transaccional (MailHog).

---

## 2. Configuración y Variables de Entorno (`.env`)

Toda la infraestructura está desacoplada de valores fijos en el archivo [`docker-compose.yml`](file:///c:/dev/tiko-qams/infra/dockers/docker-compose.yml), utilizando variables de entorno con valores por defecto (*fallbacks*):

| Variable | Descripción | Valor por Defecto / Ejemplo |
| :--- | :--- | :--- |
| `POSTGRES_USER` | Usuario administrador de PostgreSQL | `qams` |
| `POSTGRES_PASSWORD` | Contraseña de acceso a la base de datos | `Qams2025!` |
| `POSTGRES_DB` | Nombre de la base de datos relacional | `qams-bd` |
| `POSTGRES_PORT` | Puerto expuesto en el host para PostgreSQL | `5432` |
| `POSTGRES_HOST` | Hostname interno del contenedor de base de datos | `postgres` |
| `REDIS_PORT` | Puerto expuesto en el host para Redis | `6379` |
| `SEQ_PORT` | Puerto expuesto para Ingesta/API de logs estructurados | `5341` |
| `SEQ_UI_PORT` | Puerto expuesto para la interfaz Web UI de Seq | `5342` |
| `MAILHOG_SMTP_PORT` | Puerto expuesto para el servidor SMTP de MailHog | `1025` |
| `MAILHOG_UI_PORT` | Puerto expuesto para la consola web de MailHog | `8025` |
| `NGINX_HTTP_PORT` | Puerto HTTP para redirección automática a HTTPS | `8080` |
| `NGINX_HTTPS_PORT` | Puerto HTTPS seguro de entrada (SSL/TLS) | `8443` |
| `NETWORK_NAME` | Nombre de la red bridge interna de Docker | `tiko-qams_network` |

> **Nota:** Se provee el archivo plantilla [`infra/dockers/.env.example`](file:///c:/dev/tiko-qams/infra/dockers/.env.example). Para configurar el entorno local:
> ```bash
> cp infra/dockers/.env.example infra/dockers/.env
> ```

---

## 3. Matriz de Componentes de la Arquitectura

| Servicio | Contenedor | Imagen / Versión | Puertos (Host:Container) | Descripción y Función |
| :--- | :--- | :--- | :--- | :--- |
| **Nginx (Gateway)** | `tiko-qams-nginx` | `nginx:1.25-alpine` | `${NGINX_HTTP_PORT:-8080}:80`<br>`${NGINX_HTTPS_PORT:-8443}:443` | Reverse proxy, terminación SSL, redirección HTTP $\to$ HTTPS (301), caché de respuestas (`proxy_cache`) y balanceo hacia los backends. Sirve estáticos del frontend. |
| **Backend 1** | `tiko-qams-backend1` | `traefik/whoami:v1.10` | Interno (`:80`) | Nodo 1 del clúster backend para validación de balanceo y enrutamiento `/api`. |
| **Backend 2** | `tiko-qams-backend2` | `traefik/whoami:v1.10` | Interno (`:80`) | Nodo 2 del clúster backend en upstream round-robin. |
| **Frontend** | `tiko-qams-frontend` | `busybox:1.36` | Interno (`:80`) / Volumen | Generador de assets SPA montados en `frontend_dist` y servidor ligero `httpd -p 80`. |
| **PostgreSQL** | `tiko-qams-postgres` | `postgres:14-alpine` | `${POSTGRES_PORT:-5432}:5432` | Base de datos relacional principal con persistencia en `postgres_data`. Carga variables mediante `env_file: .env`. Healthcheck activo con `pg_isready`. |
| **Backup Runner** | `tiko-qams-backup` | `postgres:14-alpine` | Interno | Servicio que ejecuta periódicamente `backup.sh` cada 6 horas con rotación mayor a 7 días. Conectado a la base de datos vía `${PGHOST}`. |
| **Redis** | `tiko-qams-redis` | `redis:7-alpine` | `${REDIS_PORT:-6379}:6379` | Almacén en memoria con persistencia en volumen `redis_data`. Healthcheck con `redis-cli ping`. |
| **Seq** | `tiko-qams-seq` | `datalust/seq:2023.4` | `${SEQ_PORT:-5341}:5341`<br>`${SEQ_UI_PORT:-5342}:80` | Servidor de ingesta e indexación de logs estructurados con persistencia en volumen `seq_data`. |
| **MailHog** | `tiko-qams-mailhog` | `mailhog/mailhog:v1.0.1` | `${MAILHOG_SMTP_PORT:-1025}:1025`<br>`${MAILHOG_UI_PORT:-8025}:8025` | Servidor SMTP mock y panel web con healthcheck HTTP spider. |

---

## 4. Topología de Red y Volúmenes

### Red
* **`tiko-qams_network`**: Red tipo `bridge` privada para intercomunicación por DNS interno entre todos los contenedores.

### Volúmenes Persistentes
* **`postgres_data`**: Persistencia de las bases de datos y catálogos de PostgreSQL (`/var/lib/postgresql/data`).
* **`redis_data`**: Persistencia de snapshots y operaciones en disco para Redis (`/data`).
* **`seq_data`**: Persistencia de logs y eventos indexados de Seq (`/data`).
* **`frontend_dist`**: Volumen compartido entre el contenedor frontend y Nginx para servir la aplicación SPA.

### Montajes Bind Locales
* **`../../backups`**: Carpeta local montada en `/backups` del contenedor `tiko-qams-backup` para almacenar los volcados SQL generados.
* **`../scripts/backup.sh`**: Script montado en `/backup.sh` en modo ejecutable para realizar las copias de seguridad.
* **`../../certs`**: Directorio para certificados TLS (`cert.crt` y `cert.key`) montado en `/etc/nginx/certs:ro`.
* **`../nginx/nginx.conf`**: Configuración declarativa de Nginx montada en modo solo lectura (`:ro`).

---

## 5. Endpoints y URLs de Acceso

| Servicio | URL / Host | Protocolo / Credenciales por Defecto |
| :--- | :--- | :--- |
| **Frontend Web** | `https://localhost:8443/` | HTTPS (Certificado local autofirmado en `certs/`) |
| **API Gateway (Upstream)** | `https://localhost:8443/api/` | Balanceo round-robin entre `backend1` y `backend2` |
| **Health Check Infra** | `https://localhost:8443/health` | HTTP 200 OK |
| **HTTP Redirect** | `http://localhost:8080/` | Redirección 301 permanente a HTTPS (`:8443`) |
| **Panel Seq (Web UI)** | `http://localhost:5342` | Web UI para consulta y búsqueda de logs |
| **Seq Ingestion API** | `http://localhost:5341` | Endpoint de ingesta para clientes de logging |
| **Panel MailHog** | `http://localhost:8025` | Web UI (SMTP disponible en `localhost:1025`) |
| **PostgreSQL** | `localhost:5432` | Usuario: `${POSTGRES_USER}` \| DB: `${POSTGRES_DB}` |
| **Redis** | `localhost:6379` | Sin autenticación (entorno de desarrollo) |

---

## 6. Automatización de Backups de Base de Datos

El servicio `tiko-qams-backup` ejecuta el script [`backup.sh`](file:///c:/dev/tiko-qams/infra/scripts/backup.sh) con el siguiente flujo:
1. **Espera Activa (Health Gate)**: Realiza chequeos cíclicos con `pg_isready -h ${PGHOST} -U ${POSTGRES_USER} -d ${POSTGRES_DB}` hasta asegurar disponibilidad.
2. **Generación del Volcado**: Ejecuta `pg_dump -h ${PGHOST} -U ${POSTGRES_USER} -d ${POSTGRES_DB} > /backups/qams_YYYYMMDD_HHMMSS.sql`.
3. **Validación**: Verifica la creación y el tamaño del archivo con `du -h`.
4. **Política de Rotación**: Elimina automáticamente respaldos (`*.sql` y `*.dump`) con antigüedad mayor a 7 días (`find -mtime +7 -delete`).
5. **Periodicidad**: Se ejecuta automáticamente cada 6 horas (`sleep 21600`).

---

## 7. Pruebas de Validación y Verificación

### 1. Verificación de Health Check
```bash
curl.exe -k https://localhost:8443/health
```
**Respuesta esperada:**
```text
EPICA 1 INFRA FULL OK - FRONTEND + NGINX 80->443 + POSTGRESQL + REDIS + MAILHOG 1025/8025 + SEQ 5341 + BACKEND X2
```

### 2. Verificación de Redirección HTTP a HTTPS
```bash
curl.exe -I http://localhost:8080/
```
**Respuesta esperada:**
```http
HTTP/1.1 301 Moved Permanently
Location: https://localhost:8080/
```

### 3. Verificación de Balanceo de Carga API
Ejecutar varias peticiones consecutivas para observar la alternancia de nombres de host y direcciones IP de los contenedores backend:
```bash
curl.exe -k https://localhost:8443/api/
```

### 4. Verificación de Logs del Contenedor de Backup
```bash
docker logs tiko-qams-backup
```
**Salida esperada:**
```text
[Backup] Esperando Postgresql...
[Backup] Postgresql esta listo
[Backup] Starting backup to /backups/qams_...sql
[Backup] Backup completed to /backups/qams_...sql (X.XK)
[Backup] Limpieza de backups > 7 dias completada
```

### 5. Estado de los Contenedores
```bash
docker compose -f infra/dockers/docker-compose.yml ps
```

---

## 8. Diagrama de Arquitectura
El archivo fuente en formato LaTeX con el diagrama TikZ actualizado se encuentra en:
* [`arquitectura.tex`](file:///c:/dev/tiko-qams/docs/epica-1/arquitectura.tex)
