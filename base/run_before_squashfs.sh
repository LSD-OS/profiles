#!/usr/bin/env bash

script_path=$(readlink -f "${0%/*}")
work_dir="work"
lsd_os_version="base"

arch_chroot() {
    arch-chroot "${script_path}/${work_dir}/x86_64/airootfs" /bin/bash -c "${1}"
}

do_merge() {

echo "${lsd_os_version}" > "${script_path}/${work_dir}/x86_64/airootfs/etc/lsd-version"

arch_chroot "$(cat << 'EOF'

enable_openrc_services() {
    mkdir -p /etc/runlevels/default

    for s in "$@"; do
        if [ -e "/etc/init.d/$s" ]; then
            rc-update add "$s" default 2>/dev/null || ln -sfv "/etc/init.d/$s" "/etc/runlevels/default/$s"
        else
            echo "Aviso: Serviço $s não encontrado em /etc/init.d/"
        fi
    done
}

echo "##############################"
echo "#     chroot começa aqui     #"
echo "##############################"

rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux artix lsd
pacman -Sy

rm /bin/sh
ln -sfv /bin/dash /bin/sh

enable_openrc_services chrony chronyd NetworkManager

echo
echo "============================================"
tree /etc/runlevels
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
do_merge
