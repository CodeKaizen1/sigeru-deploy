#!/bin/bash
#
# modulos/backup.sh
# Gestión de respaldos: backup de la base de datos y de la configuración,
# transferencia al servidor de respaldos con verificación SHA-256, rotación
# según la política de retención y prueba de restauración.
#
# ADAPTADO 07/11/2026 para la instalación en una sola VM (ESI Buceo): el
# script original asumía siempre un servidor de respaldos remoto (VM .202)
# alcanzable por SSH. Ahora, si config/sigeru.conf deja RESPALDO_HOST="",
# el script opera en "modo local": genera, rota y verifica el .tar.gz en
# esta misma VM y NO intenta ninguna conexión SSH/rsync. Con RESPALDO_HOST
# con un valor (como en el setup de 3 VMs de Administración de Sistemas
# Operativos), el comportamiento es exactamente el mismo de siempre.

# ---------------------------------------------------------------------------
# Auxiliares internas
# ---------------------------------------------------------------------------

_bk_log() {
    mkdir -p "$BACKUP_DIR_LOCAL"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$BACKUP_LOG"
}

# NUEVO: true si hay servidor de respaldos remoto configurado
_bk_hay_remoto() {
    [ -n "${RESPALDO_HOST:-}" ]
}

# BatchMode: si falta la llave SSH falla de inmediato en vez de quedar esperando una clave (cron)
_bk_ssh() {
    ssh -n -o BatchMode=yes -o ConnectTimeout=10 "${RESPALDO_USUARIO}@${RESPALDO_HOST}" "$@"
}

# Solo se manipulan archivos con el formato de nombre que genera este mismo script
_bk_nombre_valido() {
    [[ "$1" =~ ^(sigeru|config)_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}(\.sql)?\.tar\.gz$ ]]
}

_bk_credenciales_ok() {
    [ -f "$DB_ARCHIVO_CREDENCIALES" ] && [ "$(stat -c %a "$DB_ARCHIVO_CREDENCIALES")" = "600" ]
}

# Decide si una copia se conserva según la política de retención.
# Devuelve 0 = conservar, 1 = se puede eliminar.
_bk_conservar() {
    local nombre=$1 fecha ts edad dow dia
    [[ "$nombre" =~ _([0-9]{4}-[0-9]{2}-[0-9]{2})_ ]] || return 0   # nombre raro: no se toca
    fecha="${BASH_REMATCH[1]}"
    ts=$(date -d "$fecha" +%s 2>/dev/null) || return 0
    edad=$(( ($(date +%s) - ts) / 86400 ))
    dow=$(date -d "$fecha" +%u)      # 7 = domingo
    dia=$(date -d "$fecha" +%d)      # 01 = primer dia del mes

    (( edad <= RETENCION_DIARIOS_DIAS )) && return 0
    [[ "$dow" == 7 ]] && (( edad <= RETENCION_SEMANALES_DIAS )) && return 0
    [[ "$dia" == 01 ]] && (( edad <= RETENCION_MENSUALES_DIAS )) && return 0
    return 1
}

_bk_rotar_local() {
    local f nombre borradas=0
    for f in "$BACKUP_DIR_LOCAL"/sigeru_*.tar.gz "$BACKUP_DIR_LOCAL"/config_*.tar.gz; do
        [ -e "$f" ] || continue
        nombre=$(basename "$f")
        _bk_nombre_valido "$nombre" || continue
        if ! _bk_conservar "$nombre"; then
            rm -f -- "$f" && borradas=$((borradas + 1))
        fi
    done
    _bk_log "Rotación local: $borradas copia(s) eliminada(s)"
}

_bk_rotar_remoto() {
    local lista nombre borradas=0
    if ! lista=$(_bk_ssh "ls -1 '$RESPALDO_DIR'" 2>/dev/null); then
        _bk_log "ADVERTENCIA: no se pudo listar el servidor de respaldos para rotar"
        return 1
    fi
    while IFS= read -r nombre; do
        _bk_nombre_valido "$nombre" || continue
        if ! _bk_conservar "$nombre"; then
            _bk_ssh "rm -f -- '$RESPALDO_DIR/$nombre'" && borradas=$((borradas + 1))
        fi
    done <<< "$lista"
    _bk_log "Rotación remota: $borradas copia(s) eliminada(s)"
}

# Envia el archivo al servidor de respaldos y comprueba que llegó idéntico.
# En modo local (sin RESPALDO_HOST) no se llama a esta función: la copia
# local, ya generada y rotada, es el respaldo válido.
_bk_transferir_y_verificar() {
    local archivo=$1 nombre hash_local hash_remoto
    nombre=$(basename "$archivo")

    if ! _bk_ssh "mkdir -p '$RESPALDO_DIR'"; then
        _bk_log "ERROR: sin conexión SSH con el servidor de respaldos ($RESPALDO_HOST)"
        return 1
    fi
    if ! rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=10" "$archivo" \
            "${RESPALDO_USUARIO}@${RESPALDO_HOST}:${RESPALDO_DIR}/" 2>>"$BACKUP_LOG"; then
        _bk_log "ERROR: fallo la transferencia de $nombre"
        return 1
    fi
    _bk_log "Transferido: $nombre"

    hash_local=$(sha256sum "$archivo" | cut -d' ' -f1)
    hash_remoto=$(_bk_ssh "sha256sum '$RESPALDO_DIR/$nombre'" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$hash_remoto" ] && [ "$hash_local" = "$hash_remoto" ]; then
        _bk_log "Verificación OK (SHA-256 coincide): $nombre"
    else
        _bk_log "ERROR: la copia remota no coincide con la local: $nombre"
        return 1
    fi
}

# NUEVO: verifica que el .tar.gz local no esté corrupto (reemplaza, en modo
# local, a la verificación SHA-256 contra el remoto).
_bk_verificar_local() {
    local archivo=$1
    if tar -tzf "$archivo" > /dev/null 2>>"$BACKUP_LOG"; then
        _bk_log "Verificación OK (tar -tzf íntegro, modo local): $(basename "$archivo")"
        return 0
    else
        _bk_log "ERROR: el .tar.gz generado está corrupto: $(basename "$archivo")"
        return 1
    fi
}

# Nombres de las copias locales de la base de datos, de la más nueva a la más vieja
_bk_nombres_locales_bd() {
    local f
    for f in "$BACKUP_DIR_LOCAL"/sigeru_*.sql.tar.gz; do
        [ -e "$f" ] && basename "$f"
    done | sort -r | head -10
}

# Escribe por salida estándar el .sql contenido en una copia (local o remota)
_bk_stream_sql() {
    local origen=$1 nombre=$2
    if [ "$origen" = "remoto" ]; then
        _bk_ssh "cat '$RESPALDO_DIR/$nombre'" | tar -xzOf -
    else
        tar -xzOf "$BACKUP_DIR_LOCAL/$nombre"
    fi
}

# ---------------------------------------------------------------------------
# Funciones principales
# ---------------------------------------------------------------------------

# Backup de la base de datos. También es el punto de entrada de cron (--backup).
backup_base_datos() {
    local fecha sql gz
    fecha=$(date +%Y-%m-%d_%H-%M-%S)
    sql="$BACKUP_DIR_LOCAL/sigeru_${fecha}.sql"
    gz="${sql}.tar.gz"

    mkdir -p "$BACKUP_DIR_LOCAL"
    _bk_log "===== Inicio de backup de la base $DB_NAME ====="

    if ! validar_identificador "$DB_NAME"; then
        _bk_log "ERROR: DB_NAME inválido en la configuración"; msg_error "DB_NAME inválido."; return 1
    fi
    if ! _bk_credenciales_ok; then
        _bk_log "ERROR: falta $DB_ARCHIVO_CREDENCIALES o no tiene permisos 600"
        msg_error "Faltan las credenciales de backup. Use: Bases de datos > Crear usuario de backup."
        return 1
    fi

    # --single-transaction: copia consistente sin bloquear la base mientras se respalda
    if ! mysqldump --defaults-extra-file="$DB_ARCHIVO_CREDENCIALES" \
            --single-transaction --no-tablespaces "$DB_NAME" > "$sql" 2>>"$BACKUP_LOG" \
            || [ ! -s "$sql" ]; then
        _bk_log "ERROR: fallo mysqldump"
        rm -f -- "$sql"
        msg_error "Fallo el dump de la base de datos (ver $BACKUP_LOG)."
        return 1
    fi
    _bk_log "Dump generado: $(basename "$sql")"

    if ! tar -czf "$gz" -C "$BACKUP_DIR_LOCAL" "$(basename "$sql")"; then
        _bk_log "ERROR: fallo la compresión"
        rm -f -- "$sql" "$gz"
        msg_error "Fallo la compresión."
        return 1
    fi
    rm -f -- "$sql"
    _bk_log "Comprimido: $(basename "$gz")"

    if _bk_hay_remoto; then
        if ! _bk_transferir_y_verificar "$gz"; then
            msg_error "El backup se generó localmente pero no se pudo respaldar en $RESPALDO_HOST (ver $BACKUP_LOG)."
            return 1
        fi
    else
        _bk_log "Modo local (sin servidor de respaldos remoto configurado) — se conserva solo la copia local"
        if ! _bk_verificar_local "$gz"; then
            msg_error "El backup se generó pero el .tar.gz quedó corrupto (ver $BACKUP_LOG)."
            return 1
        fi
    fi

    _bk_rotar_local
    _bk_hay_remoto && _bk_rotar_remoto
    _bk_log "===== Fin de backup ====="
    registrar_accion "Backup de base de datos $DB_NAME: $(basename "$gz")"
    msg_ok "Backup completado y verificado: $(basename "$gz")"
}

# Backup de archivos de configuración (se ejecuta a mano, ante cambios relevantes)
backup_configuracion() {
    local fecha dest p
    local -a rutas=()
    fecha=$(date +%Y-%m-%d_%H-%M-%S)
    dest="$BACKUP_DIR_LOCAL/config_${fecha}.tar.gz"
    mkdir -p "$BACKUP_DIR_LOCAL"
    _bk_log "===== Inicio de backup de configuración ====="

    for p in "${CONFIG_A_RESPALDAR[@]}"; do
        [ -e "$p" ] && rutas+=("${p#/}")     # rutas relativas a / (evita avisos de tar)
    done
    if [ "${#rutas[@]}" -eq 0 ]; then
        _bk_log "ERROR: ninguna ruta de CONFIG_A_RESPALDAR existe en este servidor"
        msg_error "No hay archivos de configuración para respaldar."
        return 1
    fi

    if ! como_root tar -czf "$dest" -C / "${rutas[@]}" 2>>"$BACKUP_LOG"; then
        _bk_log "ERROR: fallo la compresión de la configuración"
        msg_error "Fallo la compresión de la configuración."
        return 1
    fi
    como_root chown "$(id -un):$(id -gn)" "$dest"
    chmod 600 "$dest"     # la configuración puede contener datos sensibles
    _bk_log "Comprimido: $(basename "$dest") (${#rutas[@]} rutas)"

    if _bk_hay_remoto; then
        if ! _bk_transferir_y_verificar "$dest"; then
            msg_error "No se pudo respaldar en $RESPALDO_HOST (ver $BACKUP_LOG)."
            return 1
        fi
    else
        _bk_log "Modo local (sin servidor de respaldos remoto configurado) — se conserva solo la copia local"
        if ! _bk_verificar_local "$dest"; then
            msg_error "El backup de configuración quedó corrupto (ver $BACKUP_LOG)."
            return 1
        fi
    fi
    _bk_rotar_local
    _bk_hay_remoto && _bk_rotar_remoto
    _bk_log "===== Fin de backup de configuración ====="
    registrar_accion "Backup de configuración: $(basename "$dest")"
    msg_ok "Backup de configuración completado y verificado: $(basename "$dest")"
}

backup_listar() {
    echo "--- Copias locales ($BACKUP_DIR_LOCAL) ---"
    ls -lh --time-style=long-iso "$BACKUP_DIR_LOCAL"/*.tar.gz 2>/dev/null || echo "(sin copias)"
    if _bk_hay_remoto; then
        echo "--- Servidor de respaldos ($RESPALDO_HOST:$RESPALDO_DIR) ---"
        _bk_ssh "ls -lh --time-style=long-iso '$RESPALDO_DIR'" 2>/dev/null | grep -E '\.tar\.gz$' \
            || echo "(sin copias, o sin conexión con el servidor de respaldos)"
    else
        echo "--- Servidor de respaldos ---"
        echo "(modo local: no hay servidor de respaldos remoto configurado en esta instalación)"
    fi
}

# Restaura una copia en una base TEMPORAL (nunca toca la base real) para
# comprobar que el backup realmente sirve. Es la "restauración de prueba"
# prevista en la Estrategia de Respaldo.
backup_probar_restauracion() {
    local origen nombre opcion db_prueba tablas_prueba tablas_real
    local -a nombres=()
    db_prueba="${DB_NAME}_restauracion"

    validar_identificador "$DB_NAME" || { msg_error "DB_NAME inválido."; return 1; }

    if _bk_hay_remoto; then
        echo "Origen de la copia: 1) servidor de respaldos  2) copias locales"
        read -rp "Opción: " opcion
    else
        echo "Modo local: no hay servidor de respaldos remoto configurado. Se usan las copias locales."
        opcion=2
    fi
    case "$opcion" in
        1) origen="remoto"
           mapfile -t nombres < <(_bk_ssh "ls -1 '$RESPALDO_DIR'" 2>/dev/null | grep -E '^sigeru_.*\.sql\.tar\.gz$' | sort -r | head -10) ;;
        2) origen="local"
           mapfile -t nombres < <(_bk_nombres_locales_bd) ;;
        *) msg_error "Opción inválida."; return 1 ;;
    esac
    if [ "${#nombres[@]}" -eq 0 ]; then
        msg_error "No hay copias de la base de datos en ese origen."
        return 1
    fi

    echo "Últimas copias disponibles:"
    local i
    for i in "${!nombres[@]}"; do echo "  $((i + 1))) ${nombres[$i]}"; done
    read -rp "Número de copia a probar: " opcion
    if ! [[ "$opcion" =~ ^[0-9]+$ ]] || (( opcion < 1 || opcion > ${#nombres[@]} )); then
        msg_error "Selección inválida."
        return 1
    fi
    nombre="${nombres[$((opcion - 1))]}"
    _bk_nombre_valido "$nombre" || { msg_error "Nombre de copia inválido."; return 1; }

    confirmar "¿Se creará la base temporal '$db_prueba' (la base real '$DB_NAME' NO se toca). Continuar?" || return 0

    como_root mysql -e "DROP DATABASE IF EXISTS \`$db_prueba\`; CREATE DATABASE \`$db_prueba\` CHARACTER SET utf8mb4;" \
        || { msg_error "No se pudo crear la base temporal."; return 1; }

    if ! _bk_stream_sql "$origen" "$nombre" | como_root mysql "$db_prueba"; then
        msg_error "Fallo la restauración de $nombre."
        como_root mysql -e "DROP DATABASE IF EXISTS \`$db_prueba\`;"
        _bk_log "Prueba de restauración FALLIDA: $nombre"
        return 1
    fi

    tablas_prueba=$(como_root mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_prueba';")
    tablas_real=$(como_root mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';")
    echo "Tablas restauradas: $tablas_prueba (la base real tiene $tablas_real)"
    como_root mysql -e "SELECT table_name AS tabla, table_rows AS filas FROM information_schema.tables WHERE table_schema='$db_prueba' ORDER BY table_rows DESC LIMIT 10;"

    if [ "${tablas_prueba:-0}" -gt 0 ] && [ "$tablas_prueba" = "$tablas_real" ]; then
        msg_ok "La copia $nombre se restauró correctamente."
        _bk_log "Prueba de restauración OK: $nombre"
    else
        msg_error "La restauración no coincide con la base real; revisar la copia."
        _bk_log "Prueba de restauración con diferencias: $nombre"
    fi
    registrar_accion "Prueba de restauración de $nombre en $db_prueba"

    if confirmar "¿Eliminar la base temporal '$db_prueba'?"; then
        como_root mysql -e "DROP DATABASE IF EXISTS \`$db_prueba\`;" && msg_ok "Base temporal eliminada."
    fi
}

# ---------------------------------------------------------------------------
# Menú del módulo
# ---------------------------------------------------------------------------
modulo_backup_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de respaldos ---"
        _bk_hay_remoto || echo "(modo local: sin servidor de respaldos remoto configurado)"
        echo "1) Backup de la base de datos ahora"
        echo "2) Backup de la configuración del sistema"
        echo "3) Listar copias (local y servidor de respaldos)"
        echo "4) Probar restauración en una base temporal"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) backup_base_datos ;;
            2) backup_configuracion ;;
            3) backup_listar ;;
            4) backup_probar_restauracion ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
