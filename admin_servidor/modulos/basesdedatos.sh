#!/bin/bash
#
# modulos/basesdedatos.sh
# Administración del servidor MySQL: estado, consulta de bases y tablas,
# importación de scripts SQL y creación del usuario de backup con privilegios
# mínimos. Las tareas administrativas usan el acceso de root de MySQL via sudo.
#
# ADAPTADO 07/11/2026 para la instalación en una sola VM (ESI Buceo): el
# script original asumía siempre un MySQL instalado nativo en esta misma VM
# (systemctl status mysql, sudo mysql por socket local). Ahora, si
# config/sigeru.conf define SIGERU_DEPLOY_DIR (carpeta de sigeru-deploy con
# su docker-compose.yml), este módulo asume que MySQL vive en el contenedor
# "db" de ese Compose y usa "docker compose exec db mysql" en vez de
# systemctl/mysql local. Con SIGERU_DEPLOY_DIR vacío, el comportamiento es
# exactamente el mismo de siempre (MySQL nativo, como en la VM de BD de
# Administración de Sistemas Operativos).

# NUEVO: true si MySQL vive en el contenedor "db" de sigeru-deploy
_db_en_docker() {
    [ -n "${SIGERU_DEPLOY_DIR:-}" ] && [ -f "$SIGERU_DEPLOY_DIR/docker-compose.yml" ]
}

_db_admin() {
    if _db_en_docker; then
        ( cd "$SIGERU_DEPLOY_DIR" && docker compose exec -T db sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql --default-character-set=utf8mb4 "$@"' sh "$@" )

    else
        como_root mysql "$@"
    fi
}

_db_nombre_ok() {
    validar_identificador "$DB_NAME" || { msg_error "DB_NAME inválido en config/sigeru.conf."; return 1; }
}

_db_estado() {
    echo "--- Servicio MySQL ---"
    if _db_en_docker; then
        ( cd "$SIGERU_DEPLOY_DIR" && docker compose ps db )
    else
        systemctl is-active mysql 2>/dev/null || msg_error "El servicio mysql no está activo (o no está instalado)."
        systemctl status mysql --no-pager 2>/dev/null | head -n 8
    fi
}

_db_listar_bases() {
    echo "--- Bases de datos ---"
    _db_admin -e "SHOW DATABASES;"
}

_db_tablas() {
    _db_nombre_ok || return 1
    echo "--- Tablas de $DB_NAME (tamaño y filas aproximadas) ---"
    _db_admin -e "SELECT table_name AS tabla,
                         table_rows AS filas,
                         ROUND((data_length + index_length) / 1024 / 1024, 2) AS tamaño_MB
                  FROM information_schema.tables
                  WHERE table_schema = '$DB_NAME'
                  ORDER BY (data_length + index_length) DESC;"
    _db_admin -N -e "SELECT CONCAT('Tamaño total: ', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2), ' MB') FROM information_schema.tables WHERE table_schema = '$DB_NAME';"
}

_db_importar() {
    local archivo
    read -rp "Ruta del archivo .sql a importar: " archivo
    if [ ! -f "$archivo" ] || [ ! -r "$archivo" ]; then
        msg_error "El archivo no existe o no se puede leer."
        return 1
    fi
    echo "Se ejecutarán TODAS las sentencias de '$archivo' sobre el servidor MySQL."
    echo "Si las tablas ya existen con datos, la importación puede fallar o duplicar registros."
    confirmar "¿Continuar?" || return 0
    if _db_admin < "$archivo"; then
        msg_ok "Importación completada."
        registrar_accion "Importado archivo SQL: $archivo"
    else
        msg_error "La importación terminó con errores."
        return 1
    fi
}

# Crea (o actualiza) el usuario de solo lectura para backups y guarda sus
# credenciales en un archivo con permisos 600, para que ningún script tenga
# la clave escrita y mysqldump no la exponga en la línea de comandos.
#
# En modo Docker (SIGERU_DEPLOY_DIR definido) el usuario se crea con host '%'
# en vez de 'localhost': al conectar desde esta VM hacia el contenedor "db"
# publicado en 127.0.0.1:<puerto>, MySQL ve la conexión como TCP y un usuario
# restringido a 'localhost' NO autentica (esa restricción solo vale para el
# socket Unix local). Las credenciales guardadas también incluyen host/puerto
# en ese caso, para que mysqldump se conecte por TCP al contenedor.
_db_crear_usuario_backup() {
    local clave clave2 host_grant="localhost"
    _db_nombre_ok || return 1
    _db_en_docker && host_grant="%"

    echo "Usuario: $DB_USUARIO_BACKUP  |  Base: $DB_NAME  |  Permisos: SELECT, LOCK TABLES, SHOW VIEW"
    _db_en_docker && echo "(modo Docker: el usuario se crea como '$DB_USUARIO_BACKUP'@'%', MySQL corre en el contenedor db de $SIGERU_DEPLOY_DIR)"
    read -rsp "Contraseña para el usuario de backup (8-64 caracteres: letras, números y @ % ^ + = _ . , : -): " clave; echo
    read -rsp "Repita la contraseña: " clave2; echo
    if [ "$clave" != "$clave2" ]; then
        msg_error "Las contraseñas no coinciden."
        return 1
    fi
    if ! [[ "$clave" =~ ^[A-Za-z0-9@%^+=_.,:-]{8,64}$ ]]; then
        msg_error "Contraseña inválida: use 8 a 64 caracteres entre letras, números y @ % ^ + = _ . , : -"
        return 1
    fi

    if ! _db_admin <<SQL
CREATE USER IF NOT EXISTS '$DB_USUARIO_BACKUP'@'$host_grant' IDENTIFIED BY '$clave';
ALTER USER '$DB_USUARIO_BACKUP'@'$host_grant' IDENTIFIED BY '$clave';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON \`$DB_NAME\`.* TO '$DB_USUARIO_BACKUP'@'$host_grant';
FLUSH PRIVILEGES;
SQL
    then
        msg_error "No se pudo crear el usuario en MySQL."
        return 1
    fi

    ( umask 077
      {
        echo "[client]"
        echo "user=$DB_USUARIO_BACKUP"
        echo "password=\"$clave\""
        if _db_en_docker; then
            [ -n "${DB_HOST_BACKUP:-}" ] && echo "host=$DB_HOST_BACKUP"
            [ -n "${DB_PORT_BACKUP:-}" ] && echo "port=$DB_PORT_BACKUP"
        fi
      } > "$DB_ARCHIVO_CREDENCIALES"
    )
    chmod 600 "$DB_ARCHIVO_CREDENCIALES"

    if mysql --defaults-extra-file="$DB_ARCHIVO_CREDENCIALES" -e "SELECT 1;" >/dev/null 2>&1; then
        msg_ok "Usuario '$DB_USUARIO_BACKUP' listo y credenciales guardadas en $DB_ARCHIVO_CREDENCIALES (permisos 600)."
        registrar_accion "Usuario de backup MySQL configurado: $DB_USUARIO_BACKUP sobre $DB_NAME"
    else
        msg_error "El usuario se creo pero no se pudo comprobar la conexión. Si el contenedor db publica el puerto en 127.0.0.1, confirmar DB_HOST_BACKUP/DB_PORT_BACKUP en sigeru.conf."
        return 1
    fi
}

# Cuentas con las que se puede conectar a MySQL (no son los usuarios de la aplicación SiGeRU)
_db_cuentas_mysql() {
    echo "--- Cuentas de MySQL ---"
    _db_admin -e "SELECT user AS usuario, host AS origen FROM mysql.user ORDER BY user, host;"
}

# Resumen de los usuarios de la aplicación (tabla usuario) sin mostrar datos personales
_db_resumen_usuarios_app() {
    _db_nombre_ok || return 1
    echo "--- Usuarios de SiGeRU por rol y estado ---"
    _db_admin -e "SELECT rolUsuario AS rol, estadoUsuario AS estado, COUNT(*) AS cantidad FROM \`$DB_NAME\`.usuario GROUP BY rolUsuario, estadoUsuario ORDER BY rolUsuario, estadoUsuario;"
    _db_admin -N -e "SELECT CONCAT('Total de usuarios: ', COUNT(*)) FROM \`$DB_NAME\`.usuario;"
}

# Listado de usuarios de la aplicación: solo nombre, apellido, rol y estado.
# No se consultan cédula, email, teléfono, dirección ni contraseñas.
_db_listar_usuarios_app() {
    local rol limite filtro=""
    _db_nombre_ok || return 1
    read -rp "Rol a mostrar (Enter = todos; ej: administrador, chofer, jefeDeCuadrilla, operarioDeCuadrilla): " rol
    if [ -n "$rol" ]; then
        [[ "$rol" =~ ^[A-Za-z]{1,40}$ ]] || { msg_error "Rol inválido (solo letras)."; return 1; }
        filtro="WHERE rolUsuario = '$rol'"
    fi
    read -rp "Cantidad máxima de filas [20]: " limite
    limite="${limite:-20}"
    [[ "$limite" =~ ^[0-9]{1,3}$ ]] || { msg_error "Cantidad inválida (de 1 a 999)."; return 1; }
    echo "Se muestran solo nombre, apellido, rol y estado; los datos personales y las contraseñas no se consultan."
    _db_admin -e "SELECT nombreUsuario AS nombre, apellidoUsuario AS apellido, rolUsuario AS rol, estadoUsuario AS estado FROM \`$DB_NAME\`.usuario $filtro ORDER BY apellidoUsuario, nombreUsuario LIMIT $limite;"
}

modulo_basesdedatos_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de bases de datos ---"
        _db_en_docker && echo "(modo Docker: $SIGERU_DEPLOY_DIR)"
        echo "1) Estado del servicio MySQL"
        echo "2) Listar bases de datos"
        echo "3) Ver tablas y tamaño de $DB_NAME"
        echo "4) Importar un archivo .sql"
        echo "5) Crear usuario de backup (privilegios mínimos)"
        echo "6) Ver cuentas de MySQL"
        echo "7) Resumen de usuarios de SiGeRU (por rol y estado)"
        echo "8) Listar usuarios de SiGeRU (sin datos personales)"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) _db_estado ;;
            2) _db_listar_bases ;;
            3) _db_tablas ;;
            4) _db_importar ;;
            5) _db_crear_usuario_backup ;;
            6) _db_cuentas_mysql ;;
            7) _db_resumen_usuarios_app ;;
            8) _db_listar_usuarios_app ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
