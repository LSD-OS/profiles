#!/usr/bin/env bash

script_path=$(readlink -f "${0%/*}")
work_dir="work"
lsd_os_version="cosmic"
airootfs="${script_path}/${work_dir}/x86_64/airootfs"

arch_chroot() {
    arch-chroot "${airootfs}" /bin/bash -c "${1}"
}

# Gates live-only do lsd-welcome: o pacote lsd-welcome (repo [lsd]) já
# instala o script (/usr/bin/lsd-welcome) e o serviço (/etc/init.d/
# lsd-welcome) via packages.x86_64. Aqui ficam só as alterações em
# arquivos DE OUTROS PACOTES, feitas no airootfs da build — o sistema
# instalado não herda nada (o gate bloquearia o greeter em todo boot).
do_welcome() {
    # O greeter só sobe depois do welcome terminar (ou falhar). Anexado ao
    # depend do pacote cosmic-greeter-openrc apenas no airootfs da build:
    # no sistema instalado o serviço vem limpo do pacote, sem este gate.
    if [ -f "${airootfs}/etc/init.d/cosmic-greeter" ] && ! grep -q 'need.*lsd-welcome' "${airootfs}/etc/init.d/cosmic-greeter"; then
        sed -i '/need dbus/s/$/ lsd-welcome/' "${airootfs}/etc/init.d/cosmic-greeter"
        echo ">>> cosmic-greeter agora espera o lsd-welcome:"
        grep -n "need.*lsd-welcome" "${airootfs}/etc/init.d/cosmic-greeter"
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

    # tty1 é do lsd-welcome na live: desativa o agetty no tty1 para que nenhum
    # prompt dispute o teclado com a TUI do welcome. A tty1 fica com o serviço
    # lsd-welcome. As tty2-6 continuam disponíveis. O Calamares reativa no target instalado.
    if [ -f "${airootfs}/etc/inittab" ]; then
        sed -i 's|^\(c1:.*tty1.*\)|#\1|' "${airootfs}/etc/inittab"
    fi
    rm -fv "${airootfs}/etc/runlevels/default/agetty.tty1" "${airootfs}/etc/runlevels/boot/agetty.tty1"

    # Autologin do liveuser (live-only): "Iniciar ISO live" sai 0, o gate
    # (need lsd-welcome acima) solta o greetd e o primeiro run dele
    # sobe a sessão direto via [initial_session] — sem greeter pedindo
    # login (ISO live é single-user, igual às lives de outras distros).
    # Depois de um logout o greeter COSMIC assume (o runfile /run/greetd.run
    # marca o primeiro run; ver context.rs do greetd). O command é o wrapper
    # start-cosmic (pacote cosmic-session), o mesmo Exec do wayland-sessions/
    # cosmic.desktop: o cosmic-session puro morre no início (exige D-Bus de
    # sessão; o wrapper envolve num dbus-run-session e define o env).
    if [ -f "${airootfs}/etc/greetd/cosmic-greeter.toml" ] && ! grep -q 'initial_session' "${airootfs}/etc/greetd/cosmic-greeter.toml"; then
        printf '\n[initial_session]\ncommand = "/usr/bin/start-cosmic"\nuser = "liveuser"\n' \
            >> "${airootfs}/etc/greetd/cosmic-greeter.toml"
        echo ">>> Autologin do liveuser no greetd (live-only):"
        tail -4 "${airootfs}/etc/greetd/cosmic-greeter.toml"
    fi

    # Limpeza da tela inicial (Desktop) e do menu de aplicativos:
    # 1. Desativa live-session.desktop e desktop-items (evita criar README.txt e atalho na área de trabalho)
    rm -fv "${airootfs}/etc/skel/.config/autostart/live-session.desktop"
    rm -fv "${airootfs}/home/liveuser/.config/autostart/live-session.desktop"
    if [ -f "${airootfs}/usr/bin/desktop-items" ]; then
        printf '#!/bin/sh\nexit 0\n' > "${airootfs}/usr/bin/desktop-items"
        chmod 755 "${airootfs}/usr/bin/desktop-items"
    fi
    rm -rf "${airootfs}/home/liveuser/Desktop/"* "${airootfs}/etc/skel/Desktop/"* 2>/dev/null || true

    # 2. Remove o atalho redundante 'Install Artix' / 'Sistema de Instalação' do menu de apps,
    # mantendo exclusivamente o 'Install LSD_OS' (lsd-calamares.desktop)
    rm -fv "${airootfs}/usr/share/applications/calamares-config-switcher.desktop"
    rm -fv "${airootfs}/usr/share/applications/calamares.desktop"
}

do_branding() {
    echo "==> Aplicando branding LSD_OS! no OpenRC e arquivos do sistema..."

    # Atualiza o banner do OpenRC de 'Artix Linux' para 'LSD_OS!' nos binários
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

    # Atualiza identificação em /etc/lsb-release caso exista
    if [ -f "${airootfs}/etc/lsb-release" ]; then
        sed -i 's/DISTRIB_ID=.*/DISTRIB_ID="LSD_OS"/' "${airootfs}/etc/lsb-release"
        sed -i 's/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION="LSD_OS!"/' "${airootfs}/etc/lsb-release"
    fi

    # Atualiza identificação no grub caso exista
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
pacman-key --populate archlinux artix chaotic lsd
pacman -Sy

rm /bin/sh
ln -sfv /bin/dash /bin/sh

# Os serviços cosmic-greeter e cosmic-greeter-daemon vêm do pacote
# cosmic-greeter-openrc (repo [lsd]) e o lsd-welcome do pacote lsd-welcome
# (repo [lsd]). Aqui só habilitamos.
enable_openrc_services dbus elogind chrony chronyd zram lsd-welcome cosmic-greeter cosmic-greeter-daemon NetworkManager power-profiles-daemon

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
tree /etc/runlevels
echo "============================================"
echo

# Adiciona o repositorio Flathub ao Flatpak para a cosmic-store
if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    echo ">>> Repositorio Flathub adicionado ao Flatpak"
fi

# Substitui atalho padrao do firefox pelo brave nos favoritos do COSMIC
FAV_SYSTEM="/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites"
if [ -f "$FAV_SYSTEM" ]; then
    sed -i 's/"firefox"/"brave-browser"/' "$FAV_SYSTEM"
    echo ">>> Firefox substituido pelo Brave em $FAV_SYSTEM"
fi

# Garante que o usuario liveuser tambem receba a configuracao com o Brave
mkdir -p /home/liveuser/.config/cosmic/com.system76.CosmicAppList/v1
mkdir -p /etc/skel/.config/cosmic/com.system76.CosmicAppList/v1
cat << 'FAV_EOF' > /home/liveuser/.config/cosmic/com.system76.CosmicAppList/v1/favorites
[
    "brave-browser",
    "com.system76.CosmicFiles",
    "com.system76.CosmicEdit",
    "com.system76.CosmicTerm",
    "com.system76.CosmicStore",
    "com.system76.CosmicSettings",
]
FAV_EOF
cp -fv /home/liveuser/.config/cosmic/com.system76.CosmicAppList/v1/favorites /etc/skel/.config/cosmic/com.system76.CosmicAppList/v1/favorites

# Gera as pastas padrao de usuario (Downloads, Documentos, etc.) para o liveuser e no skel
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
    su liveuser -c "xdg-user-dirs-update --force"
    xdg-user-dirs-update --force
fi

# Copia configuracao predefinida do Brave (pula brave://welcome e define como padrao) para o liveuser
if [ -d /etc/skel/.config/BraveSoftware ]; then
    mkdir -p /home/liveuser/.config
    cp -r /etc/skel/.config/BraveSoftware /home/liveuser/.config/
fi
if [ -f /etc/skel/.config/brave-flags.conf ]; then
    cp -fv /etc/skel/.config/brave-flags.conf /home/liveuser/.config/
fi
if [ -f /etc/skel/.config/mimeapps.list ]; then
    cp -fv /etc/skel/.config/mimeapps.list /home/liveuser/.config/
fi

# Garante que a tela inicial (Desktop) comece limpa sem atalhos ou README.txt
rm -rf /home/liveuser/Desktop/* /etc/skel/Desktop/* 2>/dev/null || true
rm -f /home/liveuser/.config/autostart/live-session.desktop /etc/skel/.config/autostart/live-session.desktop

chown -R liveuser:liveuser /home/liveuser

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
do_branding
