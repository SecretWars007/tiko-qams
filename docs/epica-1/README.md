# Épica 1: Infraestructura Base y Entorno de Servicios

## 1. Descripción General
La **Épica 1** establece los cimientos de infraestructura del sistema **Tiko QAMS (Quality Assurance Management System)**. Provee un entorno de desarrollo y pruebas contenerizado mediante **Docker Compose**, asegurando aislamiento de dependencias, balanceo de carga, persistencia de datos, auditoría centralizada, soporte para HTTPS con certificados SSL locales y un sistema automatizado de respaldos periódicos con rotación.

---

## 2. Componentes de la Arquitectura

| Servicio | Contenedor | Imagen / Versión | Puertos (Host:Container) | Descripción y Función |
| :--- | :--- | :--- | :--- | :--- |
| **Nginx (Gateway)** | `tiko-qams-nginx` | `nginx:1.25-alpine` | `8080:80`<br>`8443:443` | Reverse proxy, terminación SSL, redirección HTTP $\to$ HTTPS (301), caché de respuestas (`proxy_cache`) y balanceo hacia los backends. Sirve estáticos del frontend. Política `restart: unless-stopped`. |
| **Backend 1** | `tiko-qams-backend1` | `traefik/whoami:v1.10` | Interno (`:80`) | Nodo 1 del clúster backend para validación de balanceo y enrutamiento `/api`. Política `restart: unless-stopped`. |
| **Backend 2** | `tiko-qams-backend2` | `traefik/whoami:v1.10` | Interno (`:80`) | Nodo 2 del clúster backend en upstream round-robin. Política `restart: unless-stopped`. |
| **Frontend** | `tiko-qams-frontend` | `busybox:1.36` | Interno (`:80`) / Volumen | Generador de assets SPA montados en `frontend_dist` y servidor ligero `httpd -p 80`. Política `restart: unless-stopped`. |
| **PostgreSQL** | `tiko-qams-postgres` | `postgres:14-alpine` | `5432:5432` | Base de datos relacional principal con persistencia en `postgres_data`. Healthcheck activo con `pg_isready`. |
| **Backup Runner** | `tiko-qams-backup` | `postgres:14-alpine` | Interno | Servicio dedicado a la ejecución periódica de volcados automáticos (`backup.sh`) cada 6 horas con rotación mayor a 7 días. Política `restart: unless-stopped`. |
| **Redis** | `tiko-qams-redis` | `redis:7-alpine` | `6379:6379` | Almacén en memoria con persistencia en volumen `redis_data`. Healthcheck con `redis-cli ping`. Política `restart: unless-stopped`. |
| **Seq** | `tiko-qams-seq` | `datalust/seq:2023.4` | `5341:5341`<br>`5342:80` | Servidor de ingesta e indexación de logs estructurados (`:5341` API/Ingesta, `:5342` Web UI) con volumen `seq_data`. Política `restart: unless-stopped`. |
| **MailHog** | `tiko-qams-mailhog` | `mailhog/mailhog:v1.0.1` | `1025:1025`<br>`8025:8025` | Servidor SMTP mock (`:1025`) y panel web (`:8025`) con healthcheck HTTP spider. Política `restart: unless-stopped`. |

---

## 3. Topología de Red y Volúmenes

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

## 4. Endpoints y URLs de Acceso

| Servicio | URL / Host | Protocolo / Credenciales |
| :--- | :--- | :--- |
| **Frontend Web** | `https://localhost:8443/` | HTTPS (Certificado local autofirmado) |
| **API Gateway (Upstream)** | `https://localhost:8443/api/` | Balanceo entre `backend1` y `backend2` |
| **Health Check Infra** | `https://localhost:8443/health` | HTTP 200 OK |
| **HTTP Redirect** | `http://localhost:8080/` | Redirección 301 permanente a HTTPS (`8443`) |
| **Panel Seq (Web UI)** | `http://localhost:5342` | Web UI para consulta y búsqueda de logs |
| **Seq Ingestion API** | `http://localhost:5341` | Endpoint de ingesta para frameworks de logging (Serilog, Winston, etc.) |
| **Panel MailHog** | `http://localhost:8025` | Web UI (SMTP disponible en `localhost:1025`) |
| **PostgreSQL** | `localhost:5432` | Usuario: `postgres` \| Password: `postgres` \| DB: `qams` |
| **Redis** | `localhost:6379` | Sin autenticación (entorno de desarrollo) |

---

## 5. Automatización de Backups de Base de Datos

El servicio `tiko-qams-backup` ejecuta el script [`backup.sh`](file:///c:/dev/tiko-qams/infra/scripts/backup.sh) con el siguiente flujo:
1. **Espera Activa (Health Gate)**: Realiza chequeos cíclicos con `pg_isready -h postgres -U postgres -d qams` hasta asegurar disponibilidad.
2. **Generación del Volcado**: Ejecuta `pg_dump -h postgres -U postgres -d qams > /backups/qams_YYYYMMDD_HHMMSS.sql`.
3. **Validación**: Verifica la creación y el tamaño del archivo con `du -h`.
4. **Política de Rotación**: Elimina automáticamente respaldos (`*.sql` y `*.dump`) con antigüedad mayor a 7 días (`find -mtime +7 -delete`).
5. **Periodicidad**: Se ejecuta automáticamente cada 6 horas (`sleep 21600`).

---

## 6. Pruebas de Validación y Verificación

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

## 7. Diagrama de Arquitectura
El archivo fuente en formato LaTeX con el diagrama TikZ actualizado se encuentra en:
* [`arquitectura.tex`](file:///c:/dev/tiko-qams/docs/epica-1/arquitectura.tex)
