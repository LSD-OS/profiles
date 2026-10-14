#!/usr/bin/env bash

script_path=$(readlink -f "${0%/*}")
work_dir="work"
lsd_os_version="cosmic"
airootfs="${script_path}/${work_dir}/x86_64/airootfs"

arch_chroot() {
    arch-chroot "${airootfs}" /bin/bash -c "${1}"
}

# Gates live-only do lsd-welcome: o pacote lsd-welcome (repo [lsd]) já
# instala o script (/usr/bin/lsd-welcome) e o serviço (/etc/dinit.d/
# lsd-welcome) via packages.x86_64. Aqui ficam só as alterações em
# arquivos DE OUTROS PACOTES, feitas no airootfs da build — o sistema
# instalado não herda nada (o gate bloquearia o greeter em todo boot).
do_welcome() {
    # O greeter só sobe depois do welcome terminar (ou falhar). Anexado ao
    # arquivo do pacote cosmic-greeter-dinit apenas no airootfs da build:
    # no sistema instalado o serviço vem limpo do pacote, sem este gate.
    if ! grep -q '^waits-for *= *lsd-welcome' "${airootfs}/etc/dinit.d/cosmic-greeter"; then
        printf 'waits-for       = lsd-welcome\n' >> "${airootfs}/etc/dinit.d/cosmic-greeter"
        echo ">>> cosmic-greeter agora espera o lsd-welcome:"
        tail -3 "${airootfs}/etc/dinit.d/cosmic-greeter"
    fi

    # Idioma escolhido no welcome -> greeter: o wrapper cosmic-greeter-start
    # (do pacote cosmic-greeter) sourcinga /etc/lsd-welcome/env antes de
    # subir o cosmic-comp. O greetd não carrega /etc/profile para o greeter,
    # por isso o hook direto no wrapper (live-only, via sed na build).
    if ! grep -q 'lsd-welcome' "${airootfs}/usr/bin/cosmic-greeter-start"; then
        sed -i '/^exec cosmic-comp/i [ -f /etc/lsd-welcome/env ] \&\& . /etc/lsd-welcome/env' \
            "${airootfs}/usr/bin/cosmic-greeter-start"
        echo ">>> cosmic-greeter-start com hook do lsd-welcome:"
        cat "${airootfs}/usr/bin/cosmic-greeter-start"
    fi
}

do_merge() {

echo "${lsd_os_version}" > "${airootfs}/etc/lsd-version"

arch_chroot "$(cat << 'EOF'

enable_dinit_services() {
    mkdir -p /etc/dinit.d/boot.d

    for s in "$@"; do
        if [ -e "/etc/dinit.d/$s" ]; then
            ln -sfv "../$s" "/etc/dinit.d/boot.d/$s"
        else
            echo "Aviso: Serviço $s não encontrado em /etc/dinit.d/"
        fi
    done
}

echo "##############################"
echo "#     chroot começa aqui     #"
echo "##############################"

rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux artix
pacman -Sy

rm /bin/sh
ln -sfv /bin/dash /bin/sh

# Os serviços cosmic-greeter e cosmic-greeter-daemon vêm do pacote
# cosmic-greeter-dinit (repo [lsd]) e o lsd-welcome do pacote lsd-welcome
# (repo [lsd]). Aqui só habilitamos.
enable_dinit_services dbus elogind chrony lsd-welcome cosmic-greeter cosmic-greeter-daemon NetworkManager

# ISO live não tem primeiro-boot: o initial setup do COSMIC não tem o que
# fazer (o lsd-welcome cobre idioma/teclado/timezone; o instalador vem
# depois, via Calamares).
if pacman -Rns --noconfirm cosmic-initial-setup > /dev/null 2>&1; then
    echo ">>> cosmic-initial-setup removido"
else
    echo "Aviso: cosmic-initial-setup não estava instalado"
fi

# Autologin NÃO fica mais na live: o lsd-welcome roda antes do greeter e o
# usuário faz login no greeter (o layout/idioma escolhidos no welcome já
# valem para ele). O autologin será implementado depois, no Calamares /
# instalação final.

echo
echo "============================================"
tree /etc/dinit.d
echo "============================================"
echo

usermod -aG users,adm,lp,power,video,network,storage,wheel,audio,sys,optical,scanner,rfkill,uucp liveuser

echo "##############################"
echo "#    chroot termina aqui     #"
echo "##############################"

EOF
)"
}

########## STARTS HERE ##########
do_welcome
do_merge
