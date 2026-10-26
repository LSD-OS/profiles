#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-cosmic}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "${SCRIPT_DIR}/${PROFILE}" ]; then
    echo "::error:: Perfil '${PROFILE}' não encontrado em ${SCRIPT_DIR}/${PROFILE}"
    echo "Perfis disponíveis:"
    for d in "${SCRIPT_DIR}"/*/; do
        [ -f "${d}profiledef.sh" ] && basename "$d"
    done
    exit 1
fi

echo "==> Construindo imagem Docker de build (lsd-builder)..."
sudo docker build -t lsd-builder -f "${SCRIPT_DIR}/Dockerfile.build" "${SCRIPT_DIR}"

USER_UID="${SUDO_UID:-$(id -u)}"
USER_GID="${SUDO_GID:-$(id -g)}"

echo "==> Compilando profile '${PROFILE}' via container Docker..."
# O mkarchiso necessita de privilégios para chroot/pacstrap e montagem de imagens
sudo docker run --rm --privileged \
    -e USER_UID="${USER_UID}" \
    -e USER_GID="${USER_GID}" \
    -v "${SCRIPT_DIR}:/build" \
    -w "/build/${PROFILE}" \
    lsd-builder -c "
        set -e
        # Garante que out e work voltem para o usuario nao-root mesmo se falhar
        cleanup_ownership() {
            chown -R \"\${USER_UID}:\${USER_GID}\" out work 2>/dev/null || true
        }
        trap cleanup_ownership EXIT

        echo '==> Limpando diretórios work e out anteriores...'
        rm -rf out work 2>/dev/null || true
        echo '==> Executando mkarchiso para o profile ${PROFILE}...'
        ./mkarchiso -v .
        echo '==> Build finalizada com sucesso! ISO gerada em ${PROFILE}/out/'
    "
