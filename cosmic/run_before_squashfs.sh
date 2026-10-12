#!/usr/bin/env bash

script_path=$(readlink -f "${0%/*}")
work_dir="work"
lsd_os_version="cosmic"

arch_chroot() {
    arch-chroot "${script_path}/${work_dir}/x86_64/airootfs" /bin/bash -c "${1}"
}

do_merge() {

echo "${lsd_os_version}" > "${script_path}/${work_dir}/x86_64/airootfs/etc/lsd-version"

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

cat << 'CONFIG_EOF' >> /etc/greetd/cosmic-greeter.toml

[initial_session]
command = "cosmic-greeter-start"
user = "liveuser"
CONFIG_EOF

enable_dinit_services dbus elogind chrony cosmic-greeter cosmic-greeter-daemon NetworkManager

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
do_merge
