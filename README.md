# sigeru-deploy (entrega UTU — base de datos externa)

Esta carpeta **no es un repo de código del proyecto** — es el "pegamento" que une los 2 repos reales (`sigeru-backend` y `sigeru-frontend`) para poder levantar **toda la app de SiGeRU con un solo `docker compose up`**, sin instalar PHP ni Node a mano.

**Esta variante NO incluye un contenedor de base de datos.** Está pensada para entregarle a un compañero que ya tiene su propia VM funcionando como servidor de MySQL (con el esquema de SiGeRU ya cargado) para la entrega de la UTU — acá solo se dockerizan las 3 APIs y los 3 frontends, y se conectan a esa base externa por variables de entorno.

## Qué incluye este paquete

```
sigeru-deploy/       <- esta carpeta (el "pegamento": compose + gateway + .env)
sigeru-backend/      <- las 3 APIs PHP (api-usuarios, api-gestion, api-recoleccion)
sigeru-frontend/     <- los 3 sitios estáticos (landing, frontend-usuarios, backoffice)
```

Las 3 carpetas tienen que quedar **hermanas** (mismo directorio padre), exactamente como están en este paquete. No hace falta XAMPP, PHP ni MySQL instalados a mano — solo Docker.

## Por qué hace falta el "gateway" (y no alcanza con levantar cada repo por separado)

El código de los 3 frontends llama a las APIs con rutas relativas (ej. `../../api-gestion/index.php` desde `backoffice/admin.html`), pensadas para cuando todo vive bajo el mismo origen, con las APIs como carpetas hermanas de los frontends (igual que en XAMPP). Si frontend y backend quedaran en 2 puertos distintos, esas llamadas romperían.

La solución, sin tocar una sola línea de código de ninguno de los 2 repos: un contenedor `gateway` (nginx) que escucha en un solo puerto (**8090**) y reparte el tráfico — `/api-usuarios/`, `/api-gestion/` y `/api-recoleccion/` van al contenedor `web` (las APIs reales), cualquier otra ruta (`/landing/`, `/backoffice/`, `/frontend-usuarios/`) va al contenedor `frontend`.

## Cómo conectarse a la base de datos externa

Cada una de las 3 APIs (`Conexion.php`) lee las credenciales de conexión por variable de entorno (`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASS`), con prioridad sobre cualquier `.env` propio del repo. El `docker-compose.yml` de esta carpeta le pasa esas 5 variables al contenedor `web` tomándolas de tu `.env` local — por eso no hace falta tocar código PHP para apuntar a la VM del compañero.

`DB_PORT` es una variable nueva (agregada junto con este paquete): si no se completa, por defecto usa 3306 (el puerto estándar de MySQL), así que solo hace falta cambiarla si la VM del compañero expone MySQL en otro puerto.

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

   Editar `.env` y completar `DB_HOST`, `DB_PORT` (si no es 3306), `DB_NAME`, `DB_USER` y `DB_PASS` con los datos reales de la VM de base de datos — pedírselos al compañero que la administra. **Este `.env` nunca se sube a git** (va a tener una contraseña real).

   > Nota de red: la VM donde se levanten estos contenedores tiene que poder alcanzar por red (misma VPN/red interna, o la IP pública si así está configurado) el host y puerto de `DB_HOST`/`DB_PORT`, y el usuario de `DB_USER` tiene que tener permiso para conectarse desde esa IP (en MySQL, el usuario está atado a un host de origen — si la conexión falla con "Access denied", lo primero a revisar es eso con el compañero que administra la VM).

3. Levantar todo:

   ```
   docker compose up --build
   ```

   La primera vez tarda unos minutos (baja las imágenes base de PHP/nginx y arma el build). Las veces siguientes arranca mucho más rápido.

4. Abrir en el navegador: **http://localhost:8090/landing/index.html** (o la IP/host de la VM en lugar de `localhost`, según desde dónde se acceda). El panel administrador: `http://localhost:8090/backoffice/admin.html`.

5. Para parar todo: `docker compose down`. Como la base de datos vive afuera (en la VM del compañero), `docker compose down` nunca borra datos reales — los contenedores que levanta este compose no tienen datos propios que perder.

## Qué quedó verificado y qué falta

Esta variante reutiliza tal cual el `Dockerfile` de `sigeru-backend` y de `sigeru-frontend`, y el mismo `gateway.conf`, ya verificados en la versión anterior (con base de datos local) documentada en `sigeru_deploy_gateway_docker_19_10_2026`. Lo nuevo acá es:

- Se quitó el contenedor `db` y las variables de conexión del contenedor `web` ahora vienen de `.env` (host/puerto/usuario/contraseña externos) en vez de apuntar al contenedor local.
- Se agregó soporte de `DB_PORT` en las 3 `Conexion.php` (antes no existía la variable; por defecto usa 3306, así que no cambia el comportamiento en ninguna instalación existente — XAMPP, Docker local, etc.).
- Se verificó con `php -l` que los 3 `Conexion.php` modificados no tienen errores de sintaxis.

**Lo que falta de verificar** (depende de la VM del compañero, no de este código): que la conexión de red desde donde se levanten los contenedores hacia `DB_HOST:DB_PORT` esté habilitada, y que el usuario de `DB_USER` tenga permiso de conexión desde esa máquina. No se pudo probar contra la VM real desde este entorno porque no se tienen sus datos de acceso — conviene correr `docker compose up --build` una vez en la máquina real y confirmar que el login y la carga de contenedores devuelven datos reales antes de dar la entrega por cerrada.
