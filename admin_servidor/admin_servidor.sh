#!/bin/bash
#
# admin_servidor.sh
# Script principal de administración del servidor - Proyecto SiGeRU
# Versión final - Administración de Sistemas Operativos, 3ra Entrega
#
# Arquitectura modular:
#   config/sigeru.conf   configuración central (único archivo a editar)
#   lib/comun.sh         funciones reutilizables (mensajes, validaciones)
#   modulos/*.sh         un archivo por area de gestión
#
# Uso:
#   ./admin_servidor.sh             menú interactivo
#   ./admin_servidor.sh --backup    backup de la base de datos sin menú (para cron)

DIR_ACTUAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_MODULOS="$DIR_ACTUAL/modulos"

# ============================================================
# CARGA DE CONFIGURACIÓN, LIBRERÍA Y MÓDULOS
# ============================================================

source "$DIR_ACTUAL/config/sigeru.conf"
source "$DIR_ACTUAL/lib/comun.sh"

source "$DIR_MODULOS/backup.sh"
source "$DIR_MODULOS/usuarios.sh"
source "$DIR_MODULOS/grupos.sh"
source "$DIR_MODULOS/redes.sh"
source "$DIR_MODULOS/basesdedatos.sh"
source "$DIR_MODULOS/firewall.sh"
source "$DIR_MODULOS/logs.sh"

# ============================================================
# MENÚ PRINCIPAL
# ============================================================

mostrar_menu() {
    echo ""
    echo "===== Administración del Servidor - SiGeRU ====="
    echo "1) Gestión de respaldos"
    echo "2) Gestión de usuarios del sistema (cuentas de Linux)"
    echo "3) Gestión de grupos del sistema"
    echo "4) Gestión de redes"
    echo "5) Gestión de bases de datos"
    echo "6) Gestión de firewall"
    echo "7) Gestión de logs del sistema"
    echo "0) Salir"
    echo "================================================="
    read -rp "Seleccione una opción: " OPCION || { echo; exit 0; }
}

menu_principal() {
    while true; do
        mostrar_menu
        case "$OPCION" in
            1) modulo_backup_ejecutar ;;
            2) modulo_usuarios_ejecutar ;;
            3) modulo_grupos_ejecutar ;;
            4) modulo_redes_ejecutar ;;
            5) modulo_basesdedatos_ejecutar ;;
            6) modulo_firewall_ejecutar ;;
            7) modulo_logs_ejecutar ;;
            0) echo "Saliendo..."; exit 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
    done
}

# ============================================================
# EJECUCIÓN
# ============================================================

# Se ejecuta como usuario normal: las llaves SSH hacia el servidor de respaldos
# son las de este usuario, y los módulos usan sudo solo cuando lo necesitan.
if [ "$EUID" -eq 0 ]; then
    msg_error "No ejecute este script como root. Use su usuario normal (los módulos piden sudo cuando hace falta)."
    exit 1
fi

case "${1:-}" in
    "")        menu_principal ;;
    --backup)  backup_base_datos; exit $? ;;
    -h|--ayuda)
        echo "Uso: $0 [--backup]"
        echo "  (sin argumentos)  menú interactivo"
        echo "  --backup          backup de la base de datos sin menú (para cron)"
        ;;
    *) msg_error "Argumento desconocido: $1 (use --ayuda)"; exit 1 ;;
esac
