#!/usr/bin/env bash
# Despliega configs/server/ al sistema: valida, respalda y aplica solo lo cambiado.
# Uso: sudo scripts/server/deploy.sh [--dry-run]
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRY_RUN=0; [[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1
[[ $EUID -eq 0 ]] || { echo "Ejecutar con sudo"; exit 1; }

if [[ $DRY_RUN -eq 0 && -n "$(git -C "$REPO" status --porcelain configs/server)" ]]; then
  echo "Hay cambios sin commit en configs/server. Haz commit antes de desplegar."
  exit 1
fi

RAMA="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
COMMIT="$(git -C "$REPO" rev-parse --short HEAD)"
BACKUP="/var/backups/empresa/$(date +%F-%H%M%S)"
LOG="/var/log/empresa-deploy.log"

# origen en el repo -> destino en el sistema
declare -A DESTINO=(
  [samba/smb.conf]=/etc/samba/smb.conf
  [nfs/exports]=/etc/exports
  [nfs/nfs.conf]=/etc/nfs.conf
  [ssh/50-empresa.conf]=/etc/ssh/sshd_config.d/50-empresa.conf
)
# servicio a reiniciar tras aplicar el cambio
declare -A SERVICIO=(
  [samba/smb.conf]="smbd nmbd"
  [nfs/exports]="nfs-server"
  [nfs/nfs.conf]="nfs-server"
  [ssh/50-empresa.conf]="ssh"
)

validar() {
  case "$1" in
    samba/smb.conf)      testparm -s >/dev/null 2>&1 ;;
    nfs/exports)         exportfs -ra ;;
    nfs/nfs.conf)        true ;;
    ssh/50-empresa.conf) sshd -t ;;
  esac
}

echo "== Despliegue desde '$RAMA' @ $COMMIT (dry-run=$DRY_RUN)"
mkdir -p "$BACKUP"
CAMBIADOS=()

for src in "${!DESTINO[@]}"; do
  dst="${DESTINO[$src]}"
  orig="$REPO/configs/server/$src"
  if [[ ! -f "$orig" ]]; then
    echo "  - sin archivo en el repo, se omite: $src"
    continue
  fi
  nombre="$(echo "$src" | tr / _)"

  if [[ -f "$dst" ]] && cmp -s "$orig" "$dst"; then
    echo "  = sin cambios: $dst"; continue
  fi
  echo "  * cambia: $dst"

  if [[ $DRY_RUN -eq 1 ]]; then
    diff -u "$dst" "$orig" || true
    continue
  fi

  [[ -f "$dst" ]] && cp -a "$dst" "$BACKUP/$nombre"
  cp "$orig" "$dst"

  if ! validar "$src"; then
    echo "  ! Validación fallida. Restaurando $dst"
    if [[ -f "$BACKUP/$nombre" ]]; then cp -a "$BACKUP/$nombre" "$dst"; else rm -f "$dst"; fi
    echo "  ! Revisa el error y vuelve a intentarlo. Respaldo en $BACKUP"
    exit 1
  fi
  CAMBIADOS+=("$src")
done

if [[ $DRY_RUN -eq 0 ]] && ((${#CAMBIADOS[@]})); then
  for src in "${CAMBIADOS[@]}"; do
    for svc in ${SERVICIO[$src]}; do
      systemctl restart "$svc" && echo "  ✓ $svc reiniciado"
    done
  done
  mkdir -p "$(dirname "$LOG")"
  echo "$(date -Is) rama=$RAMA commit=$COMMIT cambiados=${CAMBIADOS[*]} respaldo=$BACKUP" >> "$LOG"
fi

echo "== Fin. Registro en $LOG"
