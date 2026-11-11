#!/bin/bash
#
# modulos/firewall.sh
# Gestión del firewall (ufw). Medida de seguridad principal de este módulo:
# antes de activar el firewall siempre se permite el puerto SSH, para no
# quedar fuera del servidor.

_fw_disponible() {
    command -v ufw >/dev/null 2>&1 || { msg_error "ufw no está instalado (sudo apt install ufw)."; return 1; }
}

# Puerto en el que escucha realmente SSH (por defecto 22)
_fw_puerto_ssh() {
    local p
    p=$(como_root sshd -T 2>/dev/null | awk '$1 == "port" {print $2; exit}')
    echo "${p:-22}"
}

_fw_estado() {
    _fw_disponible || return 1
    como_root ufw status verbose
}

_fw_habilitar() {
    local ssh_puerto
    _fw_disponible || return 1
    ssh_puerto=$(_fw_puerto_ssh)
    echo "Antes de activar se permitirá SSH en el puerto $ssh_puerto para no perder el acceso."
    confirmar "¿Activar el firewall?" || return 0
    como_root ufw allow "${ssh_puerto}/tcp" >/dev/null
    como_root ufw --force enable && { msg_ok "Firewall activado."; registrar_accion "Firewall activado (SSH $ssh_puerto permitido)"; }
}

_fw_deshabilitar() {
    _fw_disponible || return 1
    echo "Atención: el servidor quedará sin filtrado de red."; confirmar "¿Desactivar el firewall?" || return 0
    como_root ufw disable && registrar_accion "Firewall desactivado"
}

_fw_leer_puerto_y_protocolo() {
    # Deja el resultado en las variables FW_PUERTO y FW_PROTO
    read -rp "Puerto (1-65535): " FW_PUERTO
    validar_puerto "$FW_PUERTO" || { msg_error "Puerto inválido."; return 1; }
    read -rp "Protocolo (tcp/udp) [tcp]: " FW_PROTO
    FW_PROTO="${FW_PROTO:-tcp}"
    [[ "$FW_PROTO" =~ ^(tcp|udp)$ ]] || { msg_error "Protocolo inválido."; return 1; }
}

_fw_permitir() {
    local origen
    _fw_disponible || return 1
    _fw_leer_puerto_y_protocolo || return 1
    read -rp "Permitir solo desde una IP (Enter = desde cualquier origen): " origen
    if [ -n "$origen" ]; then
        validar_ipv4 "$origen" || { msg_error "IP de origen inválida."; return 1; }
        como_root ufw allow from "$origen" to any port "$FW_PUERTO" proto "$FW_PROTO" \
            && registrar_accion "Regla: permitir $FW_PUERTO/$FW_PROTO desde $origen"
    else
        como_root ufw allow "${FW_PUERTO}/${FW_PROTO}" \
            && registrar_accion "Regla: permitir $FW_PUERTO/$FW_PROTO"
    fi
}

_fw_denegar() {
    _fw_disponible || return 1
    _fw_leer_puerto_y_protocolo || return 1
    if [ "$FW_PUERTO" = "$(_fw_puerto_ssh)" ]; then
        msg_error "No se puede denegar el puerto SSH: se perdería el acceso al servidor."
        return 1
    fi
    como_root ufw deny "${FW_PUERTO}/${FW_PROTO}" && registrar_accion "Regla: denegar $FW_PUERTO/$FW_PROTO"
}

_fw_eliminar_regla() {
    local numero
    _fw_disponible || return 1
    como_root ufw status numbered
    read -rp "Número de la regla a eliminar: " numero
    [[ "$numero" =~ ^[0-9]+$ ]] || { msg_error "Número inválido."; return 1; }
    echo "Atención: si elimina la regla de SSH podría perder el acceso remoto."
    confirmar "¿Eliminar la regla $numero?" || return 0
    como_root ufw --force delete "$numero" && registrar_accion "Regla de firewall eliminada: $numero"
}

# Reglas recomendadas según el rol del servidor dentro de la arquitectura de 3 servidores
_fw_reglas_por_rol() {
    local rol ssh_puerto
    _fw_disponible || return 1
    echo "Rol de este servidor: 1) Backend  2) Base de datos  3) Respaldo"
    read -rp "Opción: " rol
    ssh_puerto=$(_fw_puerto_ssh)

    case "$rol" in
        1|2|3) ;;
        *) msg_error "Opción inválida."; return 1 ;;
    esac
    echo "Se aplicará: bloquear todo lo entrante, permitir lo saliente y permitir SSH ($ssh_puerto/tcp)."
    case "$rol" in
        1) echo "   + Puerto 8090/tcp (app publicada vía gateway, mapeo docker-compose 8090:80)" ;;
        2) echo "   + MySQL 3306/tcp solo desde el Backend ($IP_BACKEND)" ;;
        3) echo "   + (solo SSH: recibe los respaldos por SSH/rsync)" ;;
    esac
    confirmar "¿Aplicar estas reglas?" || return 0

    como_root ufw default deny incoming >/dev/null
    como_root ufw default allow outgoing >/dev/null
    como_root ufw allow "${ssh_puerto}/tcp" >/dev/null
    case "$rol" in
        1) como_root ufw allow 8090/tcp >/dev/null ;;
        2) como_root ufw allow from "$IP_BACKEND" to any port 3306 proto tcp >/dev/null ;;
    esac
    registrar_accion "Reglas de firewall por rol aplicadas (rol $rol)"
    msg_ok "Reglas cargadas. Si el firewall está inactivo, actívelo con la opción 2."
}

modulo_firewall_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de firewall (ufw) ---"
        echo "1) Ver estado y reglas"
        echo "2) Activar firewall (permite SSH antes)"
        echo "3) Desactivar firewall"
        echo "4) Permitir un puerto"
        echo "5) Denegar un puerto"
        echo "6) Eliminar una regla"
        echo "7) Aplicar reglas recomendadas según el rol del servidor"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) _fw_estado ;;
            2) _fw_habilitar ;;
            3) _fw_deshabilitar ;;
            4) _fw_permitir ;;
            5) _fw_denegar ;;
            6) _fw_eliminar_regla ;;
            7) _fw_reglas_por_rol ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
