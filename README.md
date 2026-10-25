# Tiko QAMS (Quality Assurance Management System)

Plataforma integral para la gestión y aseguramiento de calidad (Quality Assurance Management System). Este repositorio contiene la infraestructura contenerizada, servicios base, configuración de enrutamiento seguro y herramientas de observabilidad necesarias para el desarrollo, pruebas y despliegue del ecosistema **Tiko QAMS**.

---

## 📋 Tabla de Contenidos
- [Arquitectura del Sistema](#-arquitectura-del-sistema)
- [Estructura del Repositorio](#-estructura-del-repositorio)
- [Prerrequisitos](#-prerrequisitos)
- [Inicio Rápido (Quickstart)](#-inicio-rápido-quickstart)
- [Matriz de Servicios y Puertos](#-matriz-de-servicios-y-puertos)
- [Seguridad y Certificados SSL/TLS](#-seguridad-y-certificados-ssltls)
- [Estrategia de Persistencia y Backups](#-estrategia-de-persistencia-y-backups)
- [Observabilidad y Soporte de Desarrollo](#-observabilidad-y-soporte-de-desarrollo)
- [Comandos Frecuentes](#-comandos-frecuentes)
- [Documentación de Épicas](#-documentación-de-épicas)

---

## 🏛 Arquitectura del Sistema

La solución opera bajo un esquema contenerizado orquestado mediante **Docker Compose**:
* **Ingress / Reverse Proxy**: Nginx 1.25 con soporte para TLS/HTTPS, redirección forzada desde HTTP (301), caché interna en memoria/disco (`proxy_cache`) y balanceo de carga upstream round-robin.
* **Clúster Backend**: Microservicios desacoplados balanceados detrás del path `/api` con alta disponibilidad.
* **Frontend SPA**: Distribución de interfaz de usuario desacoplada servida de forma optimizada por Nginx a través de un volumen compartido.
* **Capa de Almacenamiento**: PostgreSQL 14 (datos relacionales principales) y Redis 7 (caché de alto rendimiento y sesiones), ambos con persistencia y healthchecks activos.
* **Automatización de Backups**: Contenedor dedicado que ejecuta respaldos automáticos con `pg_dump` cada 6 horas y purga archivos mayores a 7 días.
* **Observabilidad y Entorno Dev**: Ingesta centralizada de logs en Seq y captura local de correos electrónicos transaccionales con MailHog.

---

## 📂 Estructura del Repositorio

```text
tiko-qams/
├── backups/               # Directorio local para almacenamiento de backups SQL (ignorado por Git)
├── certs/                 # Certificados SSL locales (cert.crt y cert.key para qams.local / localhost)
├── docs/                  # Documentación del proyecto
│   └── epica-1/           # Documentación y diagramas de la Épica 1
│       ├── README.md      # Detalle técnico de infraestructura base
│       └── arquitectura.tex # Diagrama de arquitectura en LaTeX (TikZ)
├── infra/                 # Infraestructura como código
│   ├── dockers/           # Orquestación de contenedores
│   │   └── docker-compose.yml # Definición de servicios, volúmenes y redes
│   ├── nginx/             # Configuraciones del Reverse Proxy
│   │   └── nginx.conf     # Reglas de enrutamiento, SSL, caché y upstream
│   └── scripts/           # Scripts operativos y de mantenimiento
│       └── backup.sh      # Script de respaldos periódicos y rotación
├── .gitignore             # Reglas de exclusión de Git (secretos, certs, logs, builds)
└── README.md              # Documento principal del repositorio
```

---

## ⚙ Prerrequisitos

* [Docker Desktop](https://www.docker.com/products/docker-desktop/) (v24+ recomendado) con Docker Compose v2.
* Git configurado.
* Cliente cURL o navegador moderno para validación de endpoints.

---

## 🚀 Inicio Rápido (Quickstart)

### 1. Clonar el repositorio
```bash
git clone <URL_DEL_REPOSITORIO>
cd tiko-qams
```

### 2. Verificar certificados SSL locales
Asegurarse de contar con los certificados de desarrollo dentro de la carpeta `certs/`:
* `certs/cert.crt`
* `certs/cert.key`

*(En caso de no contar con ellos, generarlos con OpenSSL o mkcert para el dominio `qams.local` y `localhost`)*.

### 3. Levantar los servicios
Desde la carpeta raíz del proyecto o desde `infra/dockers/`:
```bash
docker compose -f infra/dockers/docker-compose.yml up -d
```

### 4. Verificar el estado de la infraestructura
```bash
# Validar el health check general
curl.exe -k https://localhost:8443/health

# Comprobar el balanceo de carga en la API
curl.exe -k https://localhost:8443/api/

# Verificar contenedores en ejecución
docker compose -f infra/dockers/docker-compose.yml ps
```

---

## 🌐 Matriz de Servicios y Puertos

| Servicio | Contenedor | Puerto Host | Puerto Interno | Propósito |
| :--- | :--- | :--- | :--- | :--- |
| **Nginx (HTTPS)** | `tiko-qams-nginx` | **8443** | 443 | Entrada principal segura, Frontend y API Gateway |
| **Nginx (HTTP)** | `tiko-qams-nginx` | **8080** | 80 | Redirección 301 a HTTPS |
| **Backend 1** | `tiko-qams-backend1` | - | 80 | Réplica A en upstream `/api` |
| **Backend 2** | `tiko-qams-backend2` | - | 80 | Réplica B en upstream `/api` |
| **Frontend** | `tiko-qams-frontend` | - | 80 | Servidor ligero y generador de assets en `frontend_dist` |
| **PostgreSQL** | `tiko-qams-postgres` | **5432** | 5432 | Base de datos relacional principal |
| **Backup Runner** | `tiko-qams-backup` | - | - | Tarea programada cada 6h para volcado de base de datos |
| **Redis** | `tiko-qams-redis` | **6379** | 6379 | Memoria caché y almacén de sesiones |
| **Seq (Web UI)** | `tiko-qams-seq` | **5342** | 80 | Panel web de consulta y auditoría de eventos |
| **Seq (Ingesta)** | `tiko-qams-seq` | **5341** | 5341 | Endpoint para clientes de logging (Serilog, Winston, etc.) |
| **MailHog (Web UI)** | `tiko-qams-mailhog` | **8025** | 8025 | Bandeja de entrada web para correos de prueba |
| **MailHog (SMTP)** | `tiko-qams-mailhog` | **1025** | 1025 | Servidor SMTP para envío desde aplicaciones |

---

## 🔒 Seguridad y Certificados SSL/TLS

El proxy inverso Nginx está configurado con terminación SSL obligatoria:
* Las solicitudes dirigidas a `http://localhost:8080/` son redirigidas con código **301 Moved Permanently** hacia `https://localhost:8443/`.
* Los certificados y llaves privadas residen en la carpeta `certs/` y se encuentran excluidos del control de versiones por motivos de seguridad en el archivo [`.gitignore`](file:///.gitignore).

---

## 💾 Estrategia de Persistencia y Backups

### Volúmenes Docker
* **`postgres_data`**: Mantiene la integridad y el almacenamiento permanente de las bases de datos de PostgreSQL.
* **`redis_data`**: Persiste datos y snapshots de Redis en disco (`/data`).
* **`seq_data`**: Conserva el historial de eventos e índices de búsqueda de Seq.
* **`frontend_dist`**: Almacén compartido para servir la aplicación cliente desde Nginx.

### Respaldos Automatizados (`infra/scripts/backup.sh`)
El contenedor `tiko-qams-backup` realiza las siguientes operaciones continuas:
1. Valida disponibilidad del motor mediante `pg_isready`.
2. Genera un archivo con timestamp: `/backups/qams_YYYYMMDD_HHMMSS.sql`.
3. Registra el tamaño final del archivo en los logs del contenedor.
4. Aplica una política de retención eliminando automáticamente respaldos con más de **7 días** de antigüedad.
5. Se repite cíclicamente cada **6 horas** (`sleep 21600`).

---

## 🔍 Observabilidad y Soporte de Desarrollo

* **Seq**: Accede a [http://localhost:5342](http://localhost:5342) para visualizar los logs estructurados generados por los servicios backend.
* **MailHog**: Accede a [http://localhost:8025](http://localhost:8025) para interceptar correos electrónicos emitidos por los microservicios sin riesgo de entrega a destinatarios reales.

---

## 🛠 Comandos Frecuentes

```bash
# Iniciar todos los servicios en segundo plano
docker compose -f infra/dockers/docker-compose.yml up -d

# Detener los servicios
docker compose -f infra/dockers/docker-compose.yml down

# Ver logs en tiempo real de todos los servicios
docker compose -f infra/dockers/docker-compose.yml logs -f

# Ver logs de respaldos
docker logs tiko-qams-backup

# Reiniciar únicamente Nginx
docker compose -f infra/dockers/docker-compose.yml restart nginx
```

---

## 📖 Documentación de Épicas

Para consultar el detalle de las fases de desarrollo e hitos arquitectónicos:
* [Épica 1: Infraestructura Base y Servicios Centrales](file:///c:/dev/tiko-qams/docs/epica-1/README.md)
* [Diagrama de Arquitectura en LaTeX (TikZ)](file:///c:/dev/tiko-qams/docs/epica-1/arquitectura.tex)
