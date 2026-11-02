#!/usr/bin/env bash
# Grupos, usuarios, carpetas y ACL del proyecto. Idempotente.
# No gestiona contraseñas: se asignan a mano con passwd y smbpasswd.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Ejecutar con sudo"; exit 1; }

crear_grupo() {   # nombre gid
  getent group "$1" >/dev/null || groupadd -g "$2" "$1"
}
crear_usuario() { # nombre uid grupo shell homeflag(-m|-M)
  id "$1" >/dev/null 2>&1 || useradd "$5" -u "$2" -g "$3" -s "$4" "$1"
}

# Departamentos (DEC-004)
crear_grupo finanzas 3001
crear_grupo rrhh     3002
crear_grupo venta   3003
crear_grupo sistemas    3004

# Usuarios (DEC-004)
crear_usuario alfonso 2001 sistemas   /bin/bash      -m
crear_usuario jazmin  2002 finanzas /usr/sbin/nologin -M
crear_usuario luis    2003 rrhh    /usr/sbin/nologin -M
crear_usuario zabdiel 2004 venta   /usr/sbin/nologin -M

# Administrador del servidor (DEC-003)
usermod -aG sudo alfonso

# Carpetas departamentales
BASE=/srv/empresa
mkdir -p "$BASE"
chown root:root "$BASE"; chmod 755 "$BASE"
for d in soporte-iot calidad fullstack sistemas; do
  mkdir -p "$BASE/$d"
  chown "root:$d" "$BASE/$d"
  chmod 2770 "$BASE/$d"
done

# sistemas accede a todas las carpetas departamentales (acceso y herencia)
for d in soporte-iot calidad fullstack; do
  setfacl -m  g:sistemas:rwx "$BASE/$d"
  setfacl -d -m g:sistemas:rwx "$BASE/$d"
done
