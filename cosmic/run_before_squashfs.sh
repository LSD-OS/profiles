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

# Os serviços cosmic-greeter e cosmic-greeter-daemon vêm do pacote
# cosmic-greeter-dinit (repo [lsd]); aqui só habilitamos.
enable_dinit_services dbus elogind chrony cosmic-greeter cosmic-greeter-daemon NetworkManager

# Autologin do liveuser: o greetd sobe a sessão direto no boot
# ([initial_session]) e, depois de um logout, volta pro greeter COSMIC.
# Equivale ao AutomaticLogin do gdm / auto_login do ly.
# Importante: o command é o wrapper start-cosmic (do pacote cosmic-session),
# o mesmo Exec do wayland-sessions/cosmic.desktop que o greeter usa no login
# manual. O cosmic-session puro morre logo no início: exige um D-Bus de sessão
# (zbus Builder::session no main.rs) e, sem o wrapper que o envolve num
# dbus-run-session e define o env da sessão (XDG_SESSION_TYPE=wayland etc.),
# a sessão inicial simplesmente não sobe.
if [ -f /etc/greetd/cosmic-greeter.toml ] && ! grep -q 'initial_session' /etc/greetd/cosmic-greeter.toml; then
    cat >> /etc/greetd/cosmic-greeter.toml << 'GREETD'

[initial_session]
command = "/usr/bin/start-cosmic"
user = "liveuser"
GREETD
    echo ">>> Autologin do liveuser adicionado ao greetd:"
    grep -A2 initial_session /etc/greetd/cosmic-greeter.toml
else
    echo "Aviso: /etc/greetd/cosmic-greeter.toml ausente ou autologin já configurado"
fi

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
