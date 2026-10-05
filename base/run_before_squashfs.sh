#!/usr/bin/env bash

script_path=$(readlink -f "${0%/*}")
work_dir="work"

arch_chroot() {
    arch-chroot "${script_path}/${work_dir}/x86_64/airootfs" /bin/bash -c "${1}"
}

do_merge() {

arch_chroot "$(cat << EOF

echo "##############################"
echo "# start chrooted commandlist #"
echo "##############################"

rm -rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux artix
pacman -Sy

# Root qt style for Calamares
#mkdir -p /root/.config
#cp -rf /home/liveuser/.config/{Kvantum,qt5ct} /root/.config/

#rm -rf /usr/share/applications/calamares.desktop

# Enable services
mkdir -p /etc/dinit.d/boot.d
for s in NetworkManager networkmanager chronyd chrony lightdm; do
    if [ -f "/etc/dinit.d/$s" ]; then
        ln -sfv "../$s" "/etc/dinit.d/boot.d/$s"
    fi
done

tree /etc/dinit.d

#cp -f /usr/share/custom_applications/*.desktop /usr/share/applications/ 2>/dev/null
#rm -rf /usr/share/custom_applications

usermod -aG users,adm,lp,power,video,network,storage,wheel,audio,sys,optical,scanner,rfkill,uucp liveuser

#mv /home/liveuser/.config/fish/configlive.fish /home/liveuser/.config/fish/config.fish
#mv /home/liveuser/.config/niri/cfg/autostart_live.kdl /home/liveuser/.config/niri/cfg/autostart.kdl

echo "############################"
echo "# end chrooted commandlist #"
echo "############################"

EOF
)"
}

#################################
########## STARTS HERE ##########
#################################

do_merge
