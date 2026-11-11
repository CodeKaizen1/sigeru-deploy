#!/bin/bash
#
# modulos/grupos.sh
# Gestión de grupos del sistema operativo. Un grupo permite asignar permisos
# a varios usuarios a la vez (por ejemplo, por rol). Solo se gestionan grupos
# "normales" (GID >= 1000).

_grp_gestionable() {
    local nombre=$1 gid
    if ! validar_nombre "$nombre"; then
        msg_error "Nombre de grupo inválido (minúsculas, números, - y _; máximo 32)."
        return 1
    fi
    if ! gid=$(getent group "$nombre" | cut -d: -f3) || [ -z "$gid" ]; then
        msg_error "El grupo '$nombre' no existe."
        return 1
    fi
    if (( gid < 1000 )); then
        msg_error "'$nombre' es un grupo del sistema; no se gestiona desde este menú."
        return 1
    fi
}

_grp_usuario_existe() {
    validar_nombre "$1" || { msg_error "Nombre de usuario inválido."; return 1; }
    id "$1" &>/dev/null || { msg_error "El usuario '$1' no existe."; return 1; }
}

_grp_listar() {
    printf '%-24s %-8s %s\n' "GRUPO" "GID" "MIEMBROS"
    getent group | awk -F: '$3 >= 1000 && $3 < 65534 {printf "%-24s %-8s %s\n", $1, $3, $4}'
}

_grp_crear() {
    local nombre
    read -rp "Nombre del nuevo grupo: " nombre
    validar_nombre "$nombre" || { msg_error "Nombre inválido (minúsculas, números, - y _; máximo 32)."; return 1; }
    if getent group "$nombre" >/dev/null; then
        msg_error "El grupo '$nombre' ya existe."
        return 1
    fi
    como_root groupadd "$nombre" && { msg_ok "Grupo '$nombre' creado."; registrar_accion "Grupo creado: $nombre"; }
}

_grp_eliminar() {
    local nombre gid usuarios
    read -rp "Grupo a eliminar: " nombre
    _grp_gestionable "$nombre" || return 1
    gid=$(getent group "$nombre" | cut -d: -f3)
    usuarios=$(getent passwd | awk -F: -v g="$gid" '$4 == g {print $1}' | tr '\n' ' ')
    if [ -n "$usuarios" ]; then
        msg_error "No se puede eliminar: es el grupo principal de: $usuarios"
        return 1
    fi
    confirmar "¿Eliminar el grupo '$nombre'?" || return 0
    como_root groupdel "$nombre" && { msg_ok "Grupo eliminado."; registrar_accion "Grupo eliminado: $nombre"; }
}

_grp_agregar_usuario() {
    local usuario grupo
    read -rp "Usuario: " usuario
    _grp_usuario_existe "$usuario" || return 1
    read -rp "Grupo al que se agrega: " grupo
    _grp_gestionable "$grupo" || return 1
    como_root usermod -aG "$grupo" "$usuario" \
        && { msg_ok "'$usuario' agregado a '$grupo'."; registrar_accion "Usuario $usuario agregado al grupo $grupo"; }
}

_grp_quitar_usuario() {
    local usuario grupo
    read -rp "Usuario: " usuario
    _grp_usuario_existe "$usuario" || return 1
    read -rp "Grupo del que se quita: " grupo
    _grp_gestionable "$grupo" || return 1
    como_root gpasswd -d "$usuario" "$grupo" \
        && registrar_accion "Usuario $usuario quitado del grupo $grupo"
}

_grp_ver_miembros() {
    local nombre
    read -rp "Grupo: " nombre
    _grp_gestionable "$nombre" || return 1
    echo "Miembros de '$nombre': $(getent group "$nombre" | cut -d: -f4)"
}

_grp_ver_grupos_usuario() {
    local nombre
    read -rp "Usuario: " nombre
    _grp_usuario_existe "$nombre" || return 1
    echo "Grupos de '$nombre': $(id -nG "$nombre")"
}

# Crea los grupos base que corresponden a los roles del sistema SiGeRU
_grp_crear_roles() {
    local g
    echo "Se crearán los grupos: ${GRUPOS_ROLES[*]}"
    confirmar "¿Continuar?" || return 0
    for g in "${GRUPOS_ROLES[@]}"; do
        if getent group "$g" >/dev/null; then
            msg_info "'$g' ya existe."
        elif como_root groupadd "$g"; then
            msg_ok "Grupo '$g' creado."
            registrar_accion "Grupo de rol creado: $g"
        fi
    done
}

modulo_grupos_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de grupos del sistema (grupos de Linux) ---"
        echo "1) Listar grupos"
        echo "2) Crear grupo"
        echo "3) Eliminar grupo"
        echo "4) Agregar usuario a un grupo"
        echo "5) Quitar usuario de un grupo"
        echo "6) Ver miembros de un grupo"
        echo "7) Ver grupos de un usuario"
        echo "8) Crear grupos base de los roles de SiGeRU"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) _grp_listar ;;
            2) _grp_crear ;;
            3) _grp_eliminar ;;
            4) _grp_agregar_usuario ;;
            5) _grp_quitar_usuario ;;
            6) _grp_ver_miembros ;;
            7) _grp_ver_grupos_usuario ;;
            8) _grp_crear_roles ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
