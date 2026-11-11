#!/bin/bash
#
# modulos/usuarios.sh
# Gestión de usuarios del sistema operativo (no de la aplicación SiGeRU).
# Solo se pueden gestionar usuarios "normales" (UID >= 1000); los usuarios
# del sistema (root, www-data, mysql...) quedan protegidos.

# Valida el nombre y que el usuario exista, sea normal y (salvo permitirlo) no sea el actual
_usr_gestionable() {
    local nombre=$1 propio=${2:-no} uid
    if ! validar_nombre "$nombre"; then
        msg_error "Nombre inválido (minúsculas, números, - y _; máximo 32 caracteres)."
        return 1
    fi
    if ! uid=$(id -u "$nombre" 2>/dev/null); then
        msg_error "El usuario '$nombre' no existe."
        return 1
    fi
    if (( uid < 1000 )); then
        msg_error "'$nombre' es un usuario del sistema; no se gestiona desde este menú."
        return 1
    fi
    if [ "$propio" = "no" ] && [ "$nombre" = "$USER" ]; then
        msg_error "No se puede aplicar esta acción sobre el usuario actual ($USER)."
        return 1
    fi
}

_usr_listar() {
    printf '%-20s %-8s %s\n' "USUARIO" "UID" "CARPETA PERSONAL"
    getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {printf "%-20s %-8s %s\n", $1, $3, $6}'
}

_usr_crear() {
    local nombre
    read -rp "Nombre del nuevo usuario: " nombre
    validar_nombre "$nombre" || { msg_error "Nombre inválido (minúsculas, números, - y _; máximo 32)."; return 1; }
    if id "$nombre" &>/dev/null; then
        msg_error "El usuario '$nombre' ya existe."
        return 1
    fi
    if como_root useradd -m -s /bin/bash "$nombre"; then
        msg_ok "Usuario '$nombre' creado. Defina su contraseña:"
        como_root passwd "$nombre" || msg_info "Quedó sin contraseña (cuenta bloqueada) hasta que se defina una."
        registrar_accion "Usuario creado: $nombre"
    else
        msg_error "No se pudo crear el usuario."
        return 1
    fi
}

_usr_eliminar() {
    local nombre
    read -rp "Usuario a eliminar: " nombre
    _usr_gestionable "$nombre" || return 1
    confirmar "¿Eliminar el usuario '$nombre'?" || return 0
    if confirmar "¿Eliminar también su carpeta personal (/home/$nombre) y todo su contenido?"; then
        como_root userdel -r "$nombre" && { msg_ok "Usuario y carpeta eliminados."; registrar_accion "Usuario eliminado con carpeta: $nombre"; }
    else
        como_root userdel "$nombre" && { msg_ok "Usuario eliminado (su carpeta se conservo)."; registrar_accion "Usuario eliminado: $nombre"; }
    fi
}

_usr_bloquear() {
    local nombre
    read -rp "Usuario a bloquear: " nombre
    _usr_gestionable "$nombre" || return 1
    como_root usermod -L "$nombre" && { msg_ok "Usuario '$nombre' bloqueado."; registrar_accion "Usuario bloqueado: $nombre"; }
}

_usr_desbloquear() {
    local nombre
    read -rp "Usuario a desbloquear: " nombre
    _usr_gestionable "$nombre" || return 1
    como_root usermod -U "$nombre" && { msg_ok "Usuario '$nombre' desbloqueado."; registrar_accion "Usuario desbloqueado: $nombre"; }
}

_usr_cambiar_clave() {
    local nombre
    read -rp "Usuario: " nombre
    _usr_gestionable "$nombre" si || return 1
    como_root passwd "$nombre" && registrar_accion "Contraseña cambiada: $nombre"
}

_usr_expirar_clave() {
    local nombre
    read -rp "Usuario que deberá cambiar su contraseña en el próximo inicio de sesión: " nombre
    _usr_gestionable "$nombre" || return 1
    como_root chage -d 0 "$nombre" && { msg_ok "'$nombre' deberá cambiar su contraseña al ingresar."; registrar_accion "Contraseña expirada: $nombre"; }
}

_usr_info() {
    local nombre
    read -rp "Usuario: " nombre
    _usr_gestionable "$nombre" si || return 1
    echo "--- Identidad ---";            id "$nombre"
    echo "--- Estado de la cuenta ---";  como_root passwd -S "$nombre"
    echo "--- Últimos accesos ---";      last -n 3 "$nombre" 2>/dev/null | head -n 4
}

modulo_usuarios_ejecutar() {
    local op
    while true; do
        echo ""
        echo "--- Gestión de usuarios del sistema (cuentas de Linux) ---"
        echo "1) Listar usuarios"
        echo "2) Crear usuario"
        echo "3) Eliminar usuario"
        echo "4) Bloquear usuario"
        echo "5) Desbloquear usuario"
        echo "6) Cambiar contraseña"
        echo "7) Forzar cambio de contraseña en el próximo ingreso"
        echo "8) Ver información de un usuario"
        echo "0) Volver"
        read -rp "Opción: " op || return 0
        case "$op" in
            1) _usr_listar ;;
            2) _usr_crear ;;
            3) _usr_eliminar ;;
            4) _usr_bloquear ;;
            5) _usr_desbloquear ;;
            6) _usr_cambiar_clave ;;
            7) _usr_expirar_clave ;;
            8) _usr_info ;;
            0) return 0 ;;
            *) msg_error "Opción inválida." ;;
        esac
        pausar
    done
}
