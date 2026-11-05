#!/usr/bin/env bash

script_path=$(readlink -f "${0%/*}")
work_dir="work"
lsd_os_version="base"

airootfs="${script_path}/${work_dir}/x86_64/airootfs"

arch_chroot() {
    arch-chroot "${airootfs}" /bin/bash -c "${1}"
}

do_branding() {
    echo "==> Aplicando branding LSD_OS! no OpenRC e arquivos do sistema..."

    perl -e '
use strict;
use warnings;

for my $file (@ARGV) {
    next unless -f $file;
    open(my $fh, "+<:raw", $file) or next;
    my $data;
    { local $/; $data = <$fh>; }
    my $changed = 0;
    my $target_boot = "Artix Linux (%s)\0";
    my $target_brand = "Artix Linux\0";
    my $off_boot = index($data, $target_boot);
    if ($off_boot != -1) {
        my $repl_boot = "LSD_OS! (%s)\0";
        my $pad_boot = "\0" x (length($target_boot) - length($repl_boot));
        substr($data, $off_boot, length($target_boot), $repl_boot . $pad_boot);
        my $old_suffix = $off_boot + 11;
        my $pad_off = index($data, "\0" x 8, 0x9000);
        if ($pad_off != -1) {
            substr($data, $pad_off, 6, " (%s)\0");
            for (my $i = 0; $i < length($data) - 7; $i++) {
                my $disp = unpack("l", substr($data, $i + 3, 4));
                if ($i + 7 + $disp == $old_suffix) {
                    my $new_disp = $pad_off - ($i + 7);
                    substr($data, $i + 3, 4, pack("l", $new_disp));
                }
            }
        }
        $changed = 1;
    }
    my $off_brand = index($data, $target_brand);
    if ($off_brand != -1) {
        my $repl_brand = "LSD_OS!\0";
        my $pad_brand = "\0" x (length($target_brand) - length($repl_brand));
        substr($data, $off_brand, length($target_brand), $repl_brand . $pad_brand);
        $changed = 1;
    }
    if ($changed) {
        seek($fh, 0, 0);
        print $fh $data;
        truncate($fh, length($data));
        print ">>> Branding do OpenRC atualizado para LSD_OS! em $file\n";
    }
    close($fh);
}
' "${airootfs}/usr/bin/openrc" \
  "${airootfs}/usr/bin/openrc-run" \
  "${airootfs}/usr/bin/openrc-shutdown"

    if [ -f "${airootfs}/etc/lsb-release" ]; then
        sed -i 's/DISTRIB_ID=.*/DISTRIB_ID="LSD_OS"/' "${airootfs}/etc/lsb-release"
        sed -i 's/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION="LSD_OS!"/' "${airootfs}/etc/lsb-release"
    fi

    if [ -f "${airootfs}/etc/default/grub" ]; then
        sed -i 's/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="LSD_OS"/' "${airootfs}/etc/default/grub"
    fi
}

do_merge() {

echo "${lsd_os_version}" > "${airootfs}/etc/lsd-version"

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
do_branding
