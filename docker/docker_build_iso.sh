#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-cosmic}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Construindo imagem Docker de build (lsd-builder)..."
sudo docker build -t lsd-builder -f "${SCRIPT_DIR}/Dockerfile.build" "${SCRIPT_DIR}"

echo "==> Compilando profile ${PROFILE} via container Docker..."
# O mkarchiso necessita de privilégios para chroot/pacstrap e montagem de imagens
sudo docker run --rm --privileged \
    -v "${SCRIPT_DIR}:/build" \
    -w "/build/profiles/${PROFILE}" \
    lsd-builder -c "
        set -e
        echo '==> Limpando diretórios work e out anteriores...'
        rm -rf out work 2>/dev/null || true
        echo '==> Executando mkarchiso para o profile ${PROFILE}...'
        ./mkarchiso -v .
        echo '==> Build finalizada com sucesso! ISO gerada em profiles/${PROFILE}/out/'
    "
