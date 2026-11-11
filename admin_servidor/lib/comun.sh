#!/bin/bash
#
# lib/comun.sh
# Funciones reutilizables por todos los módulos (mensajes, confirmaciones,
# validaciones de entrada y ejecución con privilegios).

msg_info()  { echo "[INFO]  $*"; }
msg_ok()    { echo "[ OK ]  $*"; }
msg_error() { echo "[ERROR] $*" >&2; }

# Deja constancia de cada acción administrativa (quién, cuándo, qué)
registrar_accion() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$USER] $*" >> "$ADMIN_LOG" 2>/dev/null || true
}

pausar() { read -rp "Presione Enter para continuar..." _; }

# confirmar "pregunta" -> devuelve 0 solo si se responde s/S
confirmar() {
    local r
    read -rp "$1 [s/N]: " r
    [[ "$r" =~ ^[sS]$ ]]
}

# Ejecuta con sudo solo si hace falta
como_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# --- Validaciones: nunca se usa texto del usuario sin validarlo antes -------
validar_nombre()        { [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; }        # usuarios / grupos
validar_identificador() { [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]; }                 # nombres de base de datos
validar_host()          { [[ "$1" =~ ^[A-Za-z0-9.-]{1,253}$ ]]; }          # IP o nombre de host
validar_puerto()        { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }

validar_ipv4() {
    local ip=$1 octeto
    local -a partes
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS=. read -ra partes <<< "$ip"
    for octeto in "${partes[@]}"; do
        (( 10#$octeto <= 255 )) || return 1
    done
}
