#!/bin/bash
#
# modulos/logs.sh
# Consulta de logs del sistema y de SiGeRU, detección de intentos de acceso
# fallidos por SSH y configuración de la rotación de los logs propios.

_log_journal() {
    if command -v journalctl >/dev/null 2>&1; then
        como_root journalctl "$@" --no-pager
    else
        msg_error "journalctl no está disponible en este sistema."
        return 1
    fi
}

_log_numero_lineas() {
    local n
    read -rp "Cantidad de líneas [20]: " n
    n="${n:-20}"
    [[ "$n" =~ ^[0-9]{1,4}$ ]] || { msg_error "Número inválido."; return 1; }
    LOG_N="$n"
}

_log_sistema() {
    _log_numero_lineas || return 1
    _log_journal -n "$LOG_N"
}

_log_errores() {
    echo "--- Errores del sistema desde el último arranque (últimos 50) ---"
    _log_journal -p err -b | tail -n 50
}

_log_ssh_fallidos() {
    echo "--- Intentos de acceso SSH fallidos (últimos 20) ---"
    _log_journal -u ssh | grep -E "Failed|Invalid user" | tail -n 20 || true
}

_log_accesos() {
    echo "--- Últimos accesos al sistema ---"
    last -n 10
}

_log_ver_archivo() {
    local archivo=$1 titulo=$2
    echo "--- $titulo ($archivo) ---"
    if [ -f "$archivo" ]; then
        tail -n 25 "$archivo"
    else
        msg_info "Todavía no existe ese log."
    fi
}

_log_buscar() {
    local unidad patron
    read -rp "Servicio (ej: ssh, mysql, cron): " unidad
    [[ "$unidad" =~ ^[A-Za-z0-9@._-]+$ ]] || { msg_error "Nombre de servicio inválido."; return 1; }
    read -rp "Texto a buscar: " patron
    [ -n "$patron" ] || { msg_error "Texto vacío."; return 1; }
    _log_journal -u "$unidad" | grep -i -F -- "$patron" | tail -n 50 || msg_info "Sin coincidencias."
}

_log_disco() {
    echo "--- Uso de disco ---"
    df -hT /
    echo "--- Tamaño de /var/log ---"
    como_root du -sh /var/log 2>/dev/null
}

# Evita que los logs de SiGeRU crezcan sin límite
_log_configurar_rotacion() {
    local destino="/etc/logrotate.d/sigeru"
    echo "Se rotarán semanalmente (8 copias comprimidas):"
    echo "  - $BACKUP_LOG"
    echo "  - $ADMIN_LOG"
    confirmar "¿Crear $destino?" || return 0
    if como_root tee "$destino" >/dev/null <<ROT
$BACKUP_LOG $ADMIN_LOG {
    su $(id -un) $(id -gn)
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
ROT
    then
        msg_ok "Rotación de logs configurada."
        registrar_accion "Configurada rotación de logs en $destino"
    else
        msg_error "No se pudo crear $destino."
        return 1
    fi
}

modulo_logs_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de logs del sistema ---"
        echo "1) Últimas líneas del log del sistema"
        echo "2) Errores del sistema"
        echo "3) Intentos de acceso SSH fallidos"
        echo "4) Últimos accesos al sistema"
        echo "5) Log de respaldos"
        echo "6) Log de acciones administrativas"
        echo "7) Buscar texto en el log de un servicio"
        echo "8) Uso de disco"
        echo "9) Configurar rotación de logs de SiGeRU"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) _log_sistema ;;
            2) _log_errores ;;
            3) _log_ssh_fallidos ;;
            4) _log_accesos ;;
            5) _log_ver_archivo "$BACKUP_LOG" "Log de respaldos" ;;
            6) _log_ver_archivo "$ADMIN_LOG" "Log de acciones administrativas" ;;
            7) _log_buscar ;;
            8) _log_disco ;;
            9) _log_configurar_rotacion ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
