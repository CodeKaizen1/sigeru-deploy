# sigeru-deploy (entrega UTU — base de datos local, instalación en una sola VM)

Esta carpeta **no es un repo de código del proyecto** — es el "pegamento" que une los 2 repos reales (`sigeru-backend` y `sigeru-frontend`) para poder levantar **toda la app de SiGeRU con un solo `docker compose up`**, sin instalar PHP, Node ni MySQL a mano.

**Esta variante levanta su propio contenedor de base de datos** (`db`, MySQL 8). Es la pensada para la instalación de ESI Buceo: todo en un solo host Linux (app + BD + respaldo), sin depender de la red ni de una VM externa de otra persona.

## Qué incluye este paquete

```
sigeru-deploy/       <- esta carpeta (el "pegamento": compose + gateway + .env)
  admin_servidor/    <- script de administración y respaldo .tar.gz de la base
  INSTALACION.md     <- manual de instalación en Linux, paso a paso
sigeru-backend/      <- las 3 APIs PHP (api-usuarios, api-gestion, api-recoleccion)
sigeru-frontend/     <- los 3 sitios estáticos (landing, frontend-usuarios, backoffice)
```

Las 3 carpetas tienen que quedar **hermanas** (mismo directorio padre), exactamente como están en este paquete. No hace falta XAMPP, PHP ni MySQL instalados a mano — solo Docker.

## Por qué hace falta el "gateway" (y no alcanza con levantar cada repo por separado)

El código de los 3 frontends llama a las APIs con rutas relativas (ej. `../../api-gestion/index.php` desde `backoffice/admin.html`), pensadas para cuando todo vive bajo el mismo origen, con las APIs como carpetas hermanas de los frontends (igual que en XAMPP). Si frontend y backend quedaran en 2 puertos distintos, esas llamadas romperían.

La solución, sin tocar una sola línea de código de ninguno de los 2 repos: un contenedor `gateway` (nginx) que escucha en un solo puerto (**8090**) y reparte el tráfico — `/api-usuarios/`, `/api-gestion/` y `/api-recoleccion/` van al contenedor `web` (las APIs reales), cualquier otra ruta (`/landing/`, `/backoffice/`, `/frontend-usuarios/`) va al contenedor `frontend`.

## Cómo se conecta la app a la base de datos

Cada una de las 3 APIs (`Conexion.php`) lee las credenciales de conexión por variable de entorno (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`), con prioridad sobre cualquier `.env` propio del repo. El `docker-compose.yml` de esta carpeta le pasa esas variables al contenedor `web` apuntando al contenedor `db` (`DB_HOST=db`, `DB_USER=root`) — no hace falta tocar código PHP.

El puerto de MySQL (3306) queda publicado **solo en `127.0.0.1`** (loopback de la misma VM), para que un script de respaldo que corra en esa VM (`admin_servidor.sh`) pueda conectarse con `mysqldump`, sin exponer la base hacia la red.

## Cómo usarlo

1. **Copiar/clonar las 3 carpetas como hermanas** (si no vienen ya así en este paquete):

   ```
   algunacarpeta/
     sigeru-backend/
     sigeru-frontend/
     sigeru-deploy/      <- esta carpeta
   ```

2. Entrar a `sigeru-deploy` y crear el `.env` real:

   ```
   cd sigeru-deploy
   cp .env.example .env
   ```

   Editar `.env` y completar `MYSQL_ROOT_PASSWORD` con una contraseña propia de esta instalación. **Este `.env` nunca se sube a git** (va a tener una contraseña real).

3. Levantar todo:

   ```
   docker compose up --build
   ```

   La primera vez tarda unos minutos (baja las imágenes de PHP/MySQL/nginx y arma el build, además de cargar el esquema y los datos de prueba en el contenedor `db` recién creado). Las veces siguientes arranca mucho más rápido.

4. Abrir en el navegador: **http://localhost:8090/landing/index.html** (o la IP/host de la VM en lugar de `localhost`, según desde dónde se acceda). El panel administrador: `http://localhost:8090/backoffice/admin.html`.

5. Para parar sin perder datos: `docker compose stop` (o `docker compose down`, que conserva el volumen nombrado `db-datos` mientras no se use `-v`).

## Respaldo (.tar.gz)

El volumen `db-datos` persiste los datos de MySQL. El respaldo comprimido en `.tar.gz` que exige el comunicado de instalación lo genera `admin_servidor/admin_servidor.sh` (en esta misma carpeta):

- Menú **5 → 5** crea el usuario `backup_user` (solo lectura) dentro del contenedor `db` y guarda sus credenciales en `~/.sigeru_backup.cnf` (permisos 600).
- `./admin_servidor.sh --backup` hace `mysqldump` por `127.0.0.1:3306`, comprime en `~/backups_local/sigeru_<fecha>.sql.tar.gz`, verifica el archivo con `tar -tzf` y aplica la retención (7 diarios, 4 semanales, 6 mensuales). Es la misma orden que se programa en `cron`.

El paso a paso completo de la instalación en Linux está en [INSTALACION.md](INSTALACION.md).

## Qué quedó verificado y qué falta

Esta variante reutiliza tal cual el `Dockerfile` de `sigeru-backend` y de `sigeru-frontend`, y el mismo `gateway.conf`. Lo que cambia respecto a la variante de base externa (05/11/2026) es que se repuso el contenedor `db` (MySQL 8, con volumen `db-datos` y los scripts de `sigeru-backend/docker/init-db` montados en `docker-entrypoint-initdb.d`), y las variables de conexión del contenedor `web` vuelven a apuntar al contenedor local en vez de a variables externas.

**Ensayo del 11/11/2026**: instalación completa desde GitHub en un Ubuntu 24.04 limpio con Docker Engine, siguiendo [INSTALACION.md](INSTALACION.md). Resultado: los 4 contenedores levantan, se cargan las 21 tablas y los datos de prueba, responden los 3 sitios y las APIs, el login de administrador funciona, una modificación desde el panel persiste después de `docker compose down` y `up`, y `admin_servidor.sh --backup` genera un `.tar.gz` íntegro.
