# Instalación de SiGeRU en Linux (ESI Buceo 2026)

Guía para instalar SiGeRU desde cero en un servidor Linux con Docker, bajando todo desde GitHub. Sigue las 5 etapas del comunicado de instalación.

Todo se hace como un usuario normal (no root) con permisos de `sudo`. En los ejemplos el usuario es `fc` y el proyecto queda en `~/SiGeRU`.

## Etapa 1 · Preparación

### 1.1 Herramientas

```bash
docker --version
docker compose version
git --version
```

Si falta algo, instalarlo (Ubuntu 24.04):

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git mysql-client cron
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Después de `usermod`, cerrar sesión y volver a entrar para que el grupo `docker` tome efecto. `mysql-client` lo usa el script de respaldo (`mysqldump`).

### 1.2 Red

```bash
hostname -I
ping -c 2 github.com
```

Anotar la IP: es la que se usa en el navegador (`http://<IP>:8090/...`). Si no hay red, revisar `/etc/netplan/*.yaml` y aplicar con `sudo netplan apply`.

### 1.3 Obtener el código desde GitHub

Las tres carpetas tienen que quedar **hermanas** dentro de `~/SiGeRU`:

```bash
mkdir -p ~/SiGeRU && cd ~/SiGeRU
git clone https://github.com/CodeKaizen1/sigeru-backend
git clone https://github.com/CodeKaizen1/sigeru-frontend
git clone https://github.com/CodeKaizen1/sigeru-deploy
ls
```

## Etapa 2 · Despliegue

### 2.1 Variables de entorno

```bash
cd ~/SiGeRU/sigeru-deploy
cp .env.example .env
nano .env
chmod 600 .env
```

En `.env`, reemplazar `cambiar_esta_contrasenia` por una contraseña propia para el root de MySQL. Usar solo letras, números y `@ % ^ + = _ . , : -`.

Los `.env` propios de cada API (SMTP, CAPTCHA) se crean desde su ejemplo. La conexión a la base no hace falta tocarla: Docker les pasa `DB_HOST=db` y la contraseña de `.env`.

```bash
cd ~/SiGeRU/sigeru-backend
cp api-usuarios/Application/Configuration/.env.example api-usuarios/Application/Configuration/.env
cp api-gestion/Configuration/.env.example api-gestion/Configuration/.env
cp api-recoleccion/Configuration/.env.example api-recoleccion/Configuration/.env
```

### 2.2 Construir e iniciar

```bash
cd ~/SiGeRU/sigeru-deploy
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

`config --quiet` no tiene que mostrar nada. La primera vez tarda unos minutos porque baja las imágenes `php:8.2-apache`, `nginx:alpine` y `mysql:8.0`. Al final, `ps` tiene que mostrar 4 servicios corriendo:

| Servicio | Qué es |
| --- | --- |
| `db` | MySQL 8, con el volumen persistente `db-datos` |
| `web` | Apache + PHP 8.2 con las 3 APIs |
| `frontend` | nginx con landing, sitio de usuarios y backoffice |
| `gateway` | nginx que publica todo en el puerto 8090 |

Esperar a que MySQL termine de cargar el esquema y los datos de prueba:

```bash
docker compose logs db | grep "ready for connections"
```

Tienen que aparecer líneas con `port: 3306`. Si solo aparece `port: 0`, todavía está cargando: esperar y repetir.

### 2.3 Comunicación entre servicios

```bash
docker network ls | grep sigeru
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8090/landing/index.html
curl -s "http://localhost:8090/api-gestion/index.php?recurso=contenedor" | head -c 200; echo
```

El primer `curl` tiene que devolver `200`. El segundo, una respuesta JSON de la API (que pida sesión también prueba que Apache/PHP responde).

## Etapa 3 · Base de datos

```bash
cd ~/SiGeRU/sigeru-deploy
docker compose exec db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" SiGeRU -e "SHOW TABLES; SELECT COUNT(*) AS usuarios FROM usuario; SELECT COUNT(*) AS contenedores FROM contenedor;"'
```

Tienen que aparecer **21 tablas** y cantidades mayores a 0. La contraseña la toma de dentro del contenedor, así que no queda escrita en el historial.

Persistencia: `docker compose down` (sin `-v`) seguido de `docker compose up -d` conserva los datos, porque viven en el volumen `sigeru-deploy_db-datos`. **No usar `down -v` ni `docker system prune`**: borran la base.

## Etapa 4 · Respaldos (.tar.gz)

El script está en `sigeru-deploy/admin_servidor`.

### 4.1 Preparar el script (una sola vez)

```bash
cd ~/SiGeRU/sigeru-deploy/admin_servidor
chmod +x admin_servidor.sh modulos/*.sh
./admin_servidor.sh
```

En el menú: **5) Gestión de bases de datos → Crear usuario de backup**. Pide una contraseña nueva para `backup_user` (8 a 64 caracteres). El script crea el usuario dentro del contenedor `db` con permisos de solo lectura y guarda las credenciales en `~/.sigeru_backup.cnf` (permisos 600). Tiene que terminar con "Usuario 'backup_user' listo".

### 4.2 Generar el respaldo

```bash
~/SiGeRU/sigeru-deploy/admin_servidor/admin_servidor.sh --backup
ls -lh ~/backups_local/
tar -tzvf "$(ls -t ~/backups_local/*.tar.gz | head -1)"
```

Genera `~/backups_local/sigeru_<fecha>_<hora>.sql.tar.gz`, comprueba que no esté corrupto y aplica la retención (7 diarios, 4 semanales, 6 mensuales). `tar -tzvf` muestra el `.sql` que hay adentro.

### 4.3 Respaldo automático diario (opcional)

```bash
(crontab -l 2>/dev/null; echo "0 3 * * * $HOME/SiGeRU/sigeru-deploy/admin_servidor/admin_servidor.sh --backup") | crontab -
crontab -l
```

La opción lleva **dos guiones** (`--backup`).

## Etapa 5 · Verificación funcional

Desde un navegador, con la IP del servidor:

- Portal público: `http://<IP>:8090/landing/index.html`
- Acceso: `http://<IP>:8090/frontend-usuarios/login.html`
- Panel administrador: `http://<IP>:8090/backoffice/admin.html` (después de iniciar sesión como administrador)

Cuentas de prueba: las cargan `02_datos_prueba.sql` y `03_ampliar_datos_prueba.sql` (la contraseña está documentada al principio de `02_datos_prueba.sql`). Por ejemplo, el administrador `patricia.nunez@sigeru.test`.

Qué mostrar:

1. Inicio de sesión como administrador.
2. **Alta, consulta, modificación y baja** de un registro (por ejemplo un contenedor).
3. Asignar una cuadrilla a una incidencia.
4. Persistencia: `docker compose restart` y comprobar que el registro creado sigue ahí.

## Detener y volver a iniciar

```bash
cd ~/SiGeRU/sigeru-deploy
docker compose stop     # detiene, conserva todo
docker compose start    # vuelve a iniciar
```

## Problemas habituales

| Síntoma | Qué revisar |
| --- | --- |
| `permission denied` al usar `docker` | Falta cerrar sesión después de `usermod -aG docker`. |
| `Completá .env con una contraseña para MySQL` | No existe `sigeru-deploy/.env` o no tiene `MYSQL_ROOT_PASSWORD`. |
| Puerto 8090 ocupado | `sudo ss -tlnp | grep 8090` para ver qué lo usa. |
| Las APIs devuelven error de conexión | MySQL todavía está cargando: ver Etapa 2.2. |
| Cambios en los SQL de `init-db` no se aplican | Solo se cargan con el volumen vacío (primera vez). |
| El respaldo dice "falta ~/.sigeru_backup.cnf" | Hacer el paso 4.1. |
| `Access denied for user 'backup_user'` | Repetir el paso 4.1 con la misma contraseña en las dos preguntas. |
