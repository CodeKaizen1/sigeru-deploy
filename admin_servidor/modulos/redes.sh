#!/bin/bash
#
# modulos/redes.sh
# Consulta y diagnóstico de la red del servidor: interfaces, rutas, puertos en
# escucha, conectividad entre los servidores del proyecto y DNS.

_red_interfaces() {
    echo "--- Interfaces y direcciones IPv4 ---"
    ip -br -4 addr
    echo "--- Estado de los enlaces ---"
    ip -br link
}

_red_rutas() {
    echo "--- Tabla de rutas ---"
    ip route
}

_red_puertos() {
    echo "--- Puertos TCP/UDP en escucha ---"
    como_root ss -tulnp
}

_red_ping() {
    local host
    read -rp "Host o IP a probar: " host
    validar_host "$host" || { msg_error "Host inválido."; return 1; }
    ping -c 4 -W 2 "$host"
}

# Devuelve 0 si se puede abrir una conexión TCP (sin depender de nc/telnet)
_red_puerto_abierto() {
    timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

_red_probar_puerto() {
    local host puerto
    read -rp "Host o IP: " host
    validar_host "$host" || { msg_error "Host inválido."; return 1; }
    read -rp "Puerto TCP: " puerto
    validar_puerto "$puerto" || { msg_error "Puerto inválido (1-65535)."; return 1; }
    if _red_puerto_abierto "$host" "$puerto"; then
        msg_ok "$host:$puerto accesible."
    else
        msg_error "$host:$puerto NO accesible (cerrado, filtrado por firewall o sin ruta)."
    fi
}

# Comprueba, para cada servidor del proyecto, la respuesta a ping y el puerto SSH
_red_verificar_servidores() {
    local entrada ip rol ping_ok ssh_ok
    printf '%-16s %-16s %-8s %s\n' "IP" "ROL" "PING" "SSH(22)"
    for entrada in "${SERVIDORES[@]}"; do
        ip="${entrada%%|*}"
        rol="${entrada#*|}"
        ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && ping_ok="OK" || ping_ok="FALLA"
        _red_puerto_abierto "$ip" 22 && ssh_ok="OK" || ssh_ok="FALLA"
        printf '%-16s %-16s %-8s %s\n' "$ip" "$rol" "$ping_ok" "$ssh_ok"
    done
}

_red_dns() {
    echo "--- Resolución de nombres (DNS) ---"
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl status 2>/dev/null | head -n 20
    else
        cat /etc/resolv.conf
    fi
}

_red_netplan() {
    echo "--- Configuración de red persistente (netplan) ---"
    como_root sh -c 'cat /etc/netplan/*.yaml' 2>/dev/null || msg_info "No hay archivos netplan en este servidor."
}

modulo_redes_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de redes ---"
        echo "1) Ver interfaces e IP"
        echo "2) Ver tabla de rutas"
        echo "3) Ver puertos en escucha"
        echo "4) Probar conectividad (ping)"
        echo "5) Probar un puerto TCP"
        echo "6) Verificar los servidores del proyecto"
        echo "7) Ver DNS"
        echo "8) Ver configuración de red persistente (netplan)"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) _red_interfaces ;;
            2) _red_rutas ;;
            3) _red_puertos ;;
            4) _red_ping ;;
            5) _red_probar_puerto ;;
            6) _red_verificar_servidores ;;
            7) _red_dns ;;
            8) _red_netplan ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
