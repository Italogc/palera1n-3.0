#!/usr/bin/env bash

mkdir -p logs
set -e

if [[ "$@" == *"--debug"* ]]; then
    set -o xtrace
fi

{

echo "[*] Command ran:`if [ $EUID = 0 ]; then echo " sudo"; fi` ./palera1n.sh $@"

# =========
# Variables
# =========
ipsw="" # IF YOU WERE TOLD TO PUT A CUSTOM IPSW URL, PUT IT HERE. YOU CAN FIND THEM ON https://appledb.dev
version="3.0"
os=$(uname)
dir="$(pwd)/binaries/$os"
commit=$(git rev-parse --short HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)

# =========
# Functions
# =========
step() {
    for i in $(seq "$1" -1 1); do
        printf '\r\e[1;36m%s (%d) ' "$2" "$i"
        sleep 1
    done
    printf '\r\e[0m%s (0)\n' "$2"
}

_wait() {
    if [ "$1" = 'normal' ]; then
        if [ "$os" = 'Darwin' ]; then
            if ! (system_profiler SPUSBDataType 2> /dev/null | grep 'Manufacturer: Apple Inc.' >> /dev/null); then
                echo "[*] Aguardando aparelho em modo normal sem senhas de bloqueio"
            fi

            while ! (system_profiler SPUSBDataType 2> /dev/null | grep 'Manufacturer: Apple Inc.' >> /dev/null); do
                sleep 1
            done
        else
            if ! (lsusb 2> /dev/null | grep ' Apple, Inc.' >> /dev/null); then
                echo "[*] Aguardando aparelho em modo normal sem senhas de bloqueio"
            fi

            while ! (lsusb 2> /dev/null | grep ' Apple, Inc.' >> /dev/null); do
                sleep 1
            done
        fi
    elif [ "$1" = 'recovery' ]; then
        if [ "$os" = 'Darwin' ]; then
            if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (Recovery Mode):' >> /dev/null); then
                echo "[*] Aguardando aparelho para reconectar em modo recuperacao"
            fi

            while ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (Recovery Mode):' >> /dev/null); do
                sleep 1
            done
        else
            if ! (lsusb 2> /dev/null | grep 'Recovery Mode' >> /dev/null); then
                echo "[*] Aguardando aparelho para reconectar em modo recuperacao"
            fi

            while ! (lsusb 2> /dev/null | grep 'Recovery Mode' >> /dev/null); do
                sleep 1
            done
        fi

        if [ "$1" = "--tweaks" ]; then
            "$dir"/irecovery -c "setenv auto-boot false"
            "$dir"/irecovery -c "saveenv"
        else
            "$dir"/irecovery -c "setenv auto-boot true"
            "$dir"/irecovery -c "saveenv"
        fi

        if [[ "$@" == *"--semi-tethered"* ]]; then
            "$dir"/irecovery -c "setenv auto-boot true"
            "$dir"/irecovery -c "saveenv"
        fi
    fi
}

_check_dfu() {
    if [ "$os" = 'Darwin' ]; then
        if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode):' >> /dev/null); then
            echo "[-] Aparelho conectado nao esta em Modo DFU, Favor reexecute este script e tente novamente quando estiver em DFU"
            exit
        fi
    else
        if ! (lsusb 2> /dev/null | grep 'DFU Mode' >> /dev/null); then
            echo "[-] Aparelho conectado nao esta em Modo DFU, Favor reexecute este script e tente novamente quando estiver em DFU"
            exit
        fi
    fi
}

_info() {
    if [ "$1" = 'recovery' ]; then
        echo $("$dir"/irecovery -q | grep "$2" | sed "s/$2: //")
    elif [ "$1" = 'normal' ]; then
        echo $("$dir"/ideviceinfo | grep "$2: " | sed "s/$2: //")
    fi
}

_pwn() {
    pwnd=$(_info recovery PWND)
    if [ "$pwnd" = "" ]; then
        echo "[*] Pwning idevice"
        "$dir"/gaster pwn
        sleep 2
        #"$dir"/gaster reset
        #sleep 1
    fi
}

_reset() {
        echo "[*] Retirando do estado DFU"
        "$dir"/gaster reset
}

_dfuhelper() {
    echo "[*] Por favor clique em qualquer tecla para botar em modo DFU"
    read -n 1 -s
    step 3 "Iniciar"
    step 4 "Segure juntos o botao de diminuir volume + botao de desligar" &
    sleep 3
    "$dir"/irecovery -c "reset"
    step 1 "Continue segurando, nao solte ainda..."
    step 10 'Agora solte o botao de desligar, mas continue segurando o botao de diminuir volume'
    sleep 1
    
    _check_dfu
    echo "[*] Aparelho em modo DFU com sucesso!"
}

_kill_if_running() {
    if (pgrep -u root -xf "$1" &> /dev/null > /dev/null); then
        # yes, it's running as root. kill it
        sudo killall $1
    else
        if (pgrep -x "$1" &> /dev/null > /dev/null); then
            killall $1
        fi
    fi
}

_beta_url() {
    if [[ "$deviceid" == *"iPad"* ]]; then
        json=$(curl -s 'https://api.appledb.dev/ios/iPadOS;19B5060d.json')
    else
        json=$(curl -s 'https://api.appledb.dev/ios/iOS;19B5060d.json')
    fi

    sources=$(echo "$json" | $dir/jq -r '.sources')
    beta_url=$(echo "$sources" | $dir/jq -r --arg deviceid "$deviceid" '.[] | select(.type == "ota" and (.deviceMap | index($deviceid))) | .links[0].url')
    echo "$beta_url"
}

_exit_handler() {
    if [ "$os" = 'Darwin' ]; then
        if [ ! "$1" = '--dfu' ]; then
            defaults write -g ignore-devices -bool false
            defaults write com.apple.AMPDevicesAgent dontAutomaticallySyncIPods -bool false
            killall Finder
        fi
    fi
    [ $? -eq 0 ] && exit
    echo "[-] Ocorreu um erro"

    cd logs
    for file in *.log; do
        mv "$file" FAIL_${file}
    done
    cd ..

    echo "[*] Arquivo de log de falha foi criado. Para ajudar envie-nos seu arquivo de log pelo Github para correcao futura."
}
trap _exit_handler EXIT

# ===========
# Fixes
# ===========

# Prevent Finder from complaning
if [ "$os" = 'Darwin' ]; then
    defaults write -g ignore-devices -bool true
    defaults write com.apple.AMPDevicesAgent dontAutomaticallySyncIPods -bool true
    killall Finder
fi

# ===========
# Subcommands
# ===========

if [ "$1" = 'clean' ]; then
    rm -rf boot* work .tweaksinstalled
    echo "[*] Arquivos criados de boot removidos com sucesso"
    exit
elif [ "$1" = 'dfuhelper' ]; then
    echo "[*] Executando ajudante de DFU"
    _dfuhelper
    exit
elif [ "$1" = '--restorerootfs' ]; then
    echo "[*] Restaurando seu sistema root aos padroes de fabrica..."
    "$dir"/irecovery -n
    sleep 2
    echo "[*] Sucesso, agora seu aparelho rebootara normalmente."
    # clean the boot files bcs we don't need them anymore
    rm -rf boot-"$deviceid" work .tweaksinstalled
    exit
fi

# ============
# Dependencies
# ============

# Download gaster
if [ -e "$dir"/gaster ]; then
    "$dir"/gaster &> /dev/null > /dev/null | grep -q 'usb_timeout: 5' && rm "$dir"/gaster
fi

if [ ! -e "$dir"/gaster ]; then
    curl -sLO https://nightly.link/pwnd2e/gaster-3.0/workflows/makefile/main/gaster-"$os".zip
    unzip gaster-"$os".zip
    mv gaster "$dir"/
    rm -rf gaster gaster-"$os".zip
fi

# Check for pyimg4
if ! python3 -c 'import pkgutil; exit(not pkgutil.find_loader("pyimg4"))'; then
    echo '[-] pyimg4 nao esta instalado. Pressione qualquer tecla para instalar, ou segure CTRL + C para cancelar'
    read -n 1 -s
    python3 -m pip install pyimg4
fi

# ============
# Prep
# ============

# Update submodules
git submodule update --init --recursive

# Re-create work dir if it exists, else, make it
if [ -e work ]; then
    rm -rf work
    mkdir work
else
    mkdir work
fi

chmod +x "$dir"/*
#if [ "$os" = 'Darwin' ]; then
#    xattr -d com.apple.quarantine "$dir"/*
#fi

# ============
# Start
# ============

echo "palera1n | Versao $version-$branch-$commit"
echo "Editado por Nebula e Mineek | Mais codigos de ramdisk por Nathan | Aplicativo Loader por Amy, modificado br por iTalogc iOS"
echo ""

if [ ! "$1" = '--tweaks' ] && [[ "$@" == *"--semi-tethered"* ]]; then
    echo "[!] --semi-tethered não será usado com modo rootless"
    echo "    Palera1n rootless será do tipo semi-tethered"
    exit
fi

if [ "$1" = '--tweaks' ]; then
    _check_dfu
fi

if [ "$1" = '--tweaks' ] && [ ! -e ".tweaksinstalled" ] && [ ! -e ".disclaimeragree" ] && [[ ! "$@" == *"--semi-tethered"* ]]; then
        echo "!!! AVISO AVISO AVISO !!!"
    echo "ESTA FERRAMENTA FUNCIONA APENAS COM CHIPS A8x-A11 COM IOS 15.0-16.3!"
    echo "NAO NOS RESPONSABILIZAMOS CASO SEU APARELHO BRICKE, ESTE É NOSSO ÚLTIMO AVISO!"
    echo "VOCE TEM CERTEZA? DIGITE 'sim' E TECLE ENTER PARA CONTINUAR COM O JAILBREAK"
    read -r answer
    if [ "$answer" = 'sim' ]; then
        echo "VOCE REALMENTE TEM CERTEZA? NOS TE AVISAMOS!"
        echo "DIGITE 'sim' E TECLE ENTER PARA CONTINUAR"
        read -r answer
        if [ "$answer" = 'sim' ]; then
            echo "[*] Habilitando tweaks"
            tweaks=1
            touch .disclaimeragree
        else
            exit
        fi
    else
        exit
    fi
fi

# Get device's iOS version from ideviceinfo if in normal mode
if [ "$1" = '--dfu' ] || [ "$1" = '--tweaks' ]; then
    if [ -z "$2" ]; then
        echo "[-] Se usar --dfu, por favor digite na frente a versao do ios do seu aparelho"
        exit
    else
        version=$2
    fi
else
    _wait normal
    version=$(_info normal ProductVersion)
    arch=$(_info normal CPUArchitecture)
    if [ "$arch" = "arm64e" ]; then
        echo "[-] o palera1n nao, e jamais, funcionara com aparelhos A12 ou superior!"
        exit
    fi
    echo "Hello, $(_info normal ProductType) on $version!"

    echo "[*] Botando seu aparelho em modo recuperacao..."
    "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID)
    _wait recovery
fi

# Grab more info
echo "[*] Resgatando informacoes do aparelho..."
cpid=$(_info recovery CPID)
model=$(_info recovery MODEL)
deviceid=$(_info recovery PRODUCT)
if [ ! "$ipsw" = "" ]; then
    ipswurl=$ipsw
else
    ipswurl=$(curl -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$dir"/jq '.firmwares | .[] | select(.version=="'"$version"'") | .url' --raw-output)
fi

# Have the user put the device into DFU
if [ ! "$1" = '--dfu' ] && [ ! "$1" = '--tweaks' ]; then
    _dfuhelper
fi
sleep 2

# ============
# Ramdisk
# ============

# Dump blobs, and install pogo if needed
if [ ! -f blobs/"$deviceid"-"$version".shsh2 ]; then
    mkdir -p blobs

    cd ramdisk
    chmod +x sshrd.sh
    echo "[*] Criando seu ramdisk"
    ./sshrd.sh 15.6 `if [ ! "$1" = '--tweaks' ]; then echo "rootless"; fi`

    echo "[*] Bootando seu ramdisk"
    ./sshrd.sh boot
    cd ..
    # if known hosts file exists, remove it
    if [ -f ~/.ssh/known_hosts ]; then
        rm ~/.ssh/known_hosts
    fi

    # Execute the commands once the rd is booted
    if [ "$os" = 'Linux' ]; then
        sudo "$dir"/iproxy 2222 22 &
    else
        "$dir"/iproxy 2222 22 &
    fi

    if ! ("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "echo connected" &> /dev/null); then
        echo "[*] Waiting for the ramdisk to finish booting"
    fi

    while ! ("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "echo connected" &> /dev/null); do
        sleep 1
    done

    echo "[*] Despejando os blobs e instalando o Pogo"
    sleep 1
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/bin/mount_filesystems"
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "cat /dev/rdisk1" | dd of=dump.raw bs=256 count=$((0x4000)) 
    "$dir"/img4tool --convert -s blobs/"$deviceid"-"$version".shsh2 dump.raw
    rm dump.raw

    if [[ "$@" == *"--semi-tethered"* ]]; then
        echo "[*] Clonando sistema root, isto pode demorar (mais de 10 minutos)"
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/newfs_apfs -A -D -o role=r -v System /dev/disk0s1"
        sleep 2
        if [[ "$@" == *"--no-baseband"* ]]; then 
            "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_apfs /dev/disk0s1s7 /mnt8"
        else
            "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_apfs /dev/disk0s1s8 /mnt8"
        fi
        
        sleep 1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "cp -a /mnt1/. /mnt8/"
        sleep 1
        echo "[*] sistema root clonado com sucesso, continuando..."
    fi

    if [[ ! "$@" == *"--no-install"* ]]; then
        tipsdir=$("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/bin/find /mnt2/containers/Bundle/Application/ -name 'Tips.app'" 2> /dev/null)
        sleep 1
        if [ "$tipsdir" = "" ]; then
            echo "[!] Aplicativo Dicas (Tips) nao instalado. Apos seu aparelho reiniciar instale este aplicativo na AppStore e tente novamente"
            "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/reboot"
            sleep 1
            _kill_if_running iproxy
            exit
        fi
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/cp -rf /usr/local/bin/loader.app/* $tipsdir"
        sleep 1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown 33 $tipsdir/Tips"
        sleep 1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/chmod 755 $tipsdir/Tips $tipsdir/palera1nHelper"
        sleep 1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown 0 $tipsdir/palera1nHelper"
    fi

    #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram allow-root-hash-mismatch=1"
    #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram root-live-fs=1"
    if [[ "$@" == *"--semi-tethered"* ]]; then
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram auto-boot=true"
    else
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram auto-boot=false"
    fi

    has_active=$("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "ls /mnt6/active" 2> /dev/null)
    if [ ! "$has_active" = "/mnt6/active" ]; then
        echo "[!] Arquivo de ativacao inexistente! Favor use um cliente de SSH para criar"
        echo "    /mnt6/active devera conter o nome do seu UUID em /mnt6"
        echo "    Quando terminar, reinicie sua sessao SSH, e reexecute este script"
        echo "    ssh root@localhost -p 2222"
        exit
    fi
    active=$("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "cat /mnt6/active" 2> /dev/null)

    "$dir"/sshpass -p 'alpine' scp -o StrictHostKeyChecking=no -P2222 binaries/Kernel15Patcher.ios root@localhost:/mnt1/private/var/root/Kernel15Patcher.ios
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown 0 /mnt1/private/var/root/Kernel15Patcher.ios"
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/chmod 755 /mnt1/private/var/root/Kernel15Patcher.ios"

    # lets actually patch the kernel
    echo "[*] Patcheando o kernel..."
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -f /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd"
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "cp /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache.bak"
    sleep 1
    # download the kernel
    echo "[*] Baixando o BuildManifest..."
    "$dir"/pzb -g BuildManifest.plist "$ipswurl"
    echo "[*] Baixando os Caches de Kernel..."
    "$dir"/pzb -g "$(awk "/""$cpid""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl"
    mv kernelcache.release.* work/kernelcache
    if [[ "$deviceid" == "iPhone8"* ]] || [[ "$deviceid" == "iPad6"* ]]|| [[ "$deviceid" == *'iPad5'* ]]; then
        python3 -m pyimg4 im4p extract -i work/kernelcache -o work/kcache.raw --extra work/kpp.bin
    else
        python3 -m pyimg4 im4p extract -i work/kernelcache -o work/kcache.raw
    fi
    sleep 1
    "$dir"/sshpass -p 'alpine' scp -o StrictHostKeyChecking=no -P2222 work/kcache.raw root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/mnt1/private/var/root/Kernel15Patcher.ios /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched"
    "$dir"/sshpass -p 'alpine' scp -o StrictHostKeyChecking=no -P2222 root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched work/
    "$dir"/Kernel64Patcher work/kcache.patched work/kcache.patched2 -o -e -u
    sleep 1
    if [[ "$deviceid" == *'iPhone8'* ]] || [[ "$deviceid" == *'iPad6'* ]] || [[ "$deviceid" == *'iPad5'* ]]; then
        python3 -m pyimg4 im4p create -i work/kcache.patched2 -o work/kcache.im4p -f krnl --extra work/kpp.bin --lzss
    elif [[ $1 == *"--tweaks"* ]]; then
        python3 -m pyimg4 im4p create -i work/kcache.patched2 -o work/kcache.im4p -f krnl --lzss
    fi
    sleep 1
    "$dir"/sshpass -p 'alpine' scp -o StrictHostKeyChecking=no -P2222 work/kcache.im4p root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "img4 -i /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p -o /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd -M /mnt6/$active/System/Library/Caches/apticket.der"
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "rm -f /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.raw /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.patched /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kcache.im4p"

    sleep 1
    has_kernelcachd=$("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "ls /mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd" 2> /dev/null)
    if [ "$has_kernelcachd" = "/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd" ]; then
        echo "[*] Caches de Kernel customizados criados com sucesso!"
    else
        echo "[!] Caches de Kernel nao existem...? Favor nos envie os seus logs deste problema pelo Github para fix futuro..."
    fi

    rm -rf work
    mkdir work

    sleep 2
    echo "[*] Sucesso! Rebootando o seu aparelho..."
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/reboot"
    sleep 1
    _kill_if_running iproxy

    if [[ "$@" == *"--semi-tethered"* ]]; then
        _wait normal
        sleep 5

        echo "[*] Botando seu aparelho em Modo Recuperacao..."
        "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID)
    elif [ ! "$1" = '--tweaks' ]; then
        _wait normal
        sleep 5

        echo "[*] Botando seu aparelho em Modo Recuperacao..."
        "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID)
    fi
    _wait recovery
    sleep 10
    _dfuhelper
    sleep 2
fi

# ============
# Boot create
# ============

# Actually create the boot files
if [ ! -f boot-"$deviceid"/.fsboot ]; then
    rm -rf boot-"$deviceid"
fi

if [ ! -f boot-"$deviceid"/ibot.img4 ]; then
    # Downloading files, and decrypting iBSS/iBEC
    rm -rf boot-"$deviceid"
    mkdir boot-"$deviceid"

    echo "[*] Convertendo blobs..."
    "$dir"/img4tool -e -s $(pwd)/blobs/"$deviceid"-"$version".shsh2 -m work/IM4M
    cd work

    echo "[*] Baixando seu BuildManifest..."
    "$dir"/pzb -g BuildManifest.plist "$ipswurl"

    echo "[*] Baixando e descriptografando seu iBSS..."
    "$dir"/pzb -g "$(awk "/""$cpid""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl"
    "$dir"/gaster decrypt "$(awk "/""$cpid""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//')" iBSS.dec

    echo "[*] Baixando e descriptografando seu iBoot..."
    "$dir"/pzb -g "$(awk "/""$cpid""/{x=1}x&&/iBoot[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl"
    "$dir"/gaster decrypt "$(awk "/""$cpid""/{x=1}x&&/iBoot[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" ibot.dec

    echo "[*] Patcheando e assinando iBSS/iBoot"
    "$dir"/iBoot64Patcher iBSS.dec iBSS.patched
    if [[ "$@" == *"--semi-tethered"* ]]; then
        if [[ "$@" == *"--no-baseband"* ]]; then 
            "$dir"/iBoot64Patcherfsboot ibot.dec ibot.patched -b '-v keepsyms=1 debug=0x2014e rd=disk0s1s7'
        else
            "$dir"/iBoot64Patcherfsboot ibot.dec ibot.patched -b '-v keepsyms=1 debug=0x2014e rd=disk0s1s8'
        fi
    else
        "$dir"/iBoot64Patcherfsboot ibot.dec ibot.patched -b '-v keepsyms=1 debug=0x2014e'
    fi
    if [ "$os" = 'Linux' ]; then
        sed -i 's/\/\kernelcache/\/\kernelcachd/g' ibot.patched
    else
        LC_ALL=C sed -i .bak -e 's/s\/\kernelcache/s\/\kernelcachd/g' ibot.patched
        rm *.bak
    fi
    cd ..
    "$dir"/img4 -i work/iBSS.patched -o boot-"$deviceid"/iBSS.img4 -M work/IM4M -A -T ibss
    "$dir"/img4 -i work/ibot.patched -o boot-"$deviceid"/ibot.img4 -M work/IM4M -A -T `if [[ "$cpid" == *"0x801"* ]]; then echo "ibss"; else echo "ibec"; fi`

    touch boot-"$deviceid"/.fsboot
fi

# ============
# Boot device
# ============

sleep 2
_pwn
_reset
echo "[*] Bootando o aparelho..."
if [[ "$cpid" == *"0x801"* ]]; then
    sleep 1
    "$dir"/irecovery -f boot-"$deviceid"/ibot.img4
    sleep 1
    "$dir"/irecovery -c fsboot
else
    sleep 1
    "$dir"/irecovery -f boot-"$deviceid"/iBSS.img4
    sleep 1
    "$dir"/irecovery -f boot-"$deviceid"/ibot.img4
    sleep 1
    "$dir"/irecovery -c fsboot
fi

if [ "$os" = 'Darwin' ]; then
    if [ ! "$1" = '--dfu' ]; then
        defaults write -g ignore-devices -bool false
        defaults write com.apple.AMPDevicesAgent dontAutomaticallySyncIPods -bool false
        killall Finder
    fi
fi

cd logs
for file in *.log; do
    mv "$file" SUCCESS_${file}
done
cd ..

rm -rf work rdwork
echo ""
echo "Jailbrek Finalizado com Sucesso!"
echo "Seu Dispositivo será agora patcheado com seu iOS"
echo "Por seguranca mantenha seu Aparelho conectado via cabo USB neste terminal enquanto acaba de concluir os procedimentos finais abaixo"
echo "Se essa for sua primeira vez com este jailbreak, abra o aplicativo do Palerain e clique no botao INSTALL"
echo "Após isso, abra o aplicativo Palera1n novamente e clique em DO ALL nos ajustes e espere seu aparelho dar respring"
echo "Se aparecer uma janela de opcoes na tela do seu aparelho escolha ALWAYS ALLOW"
echo "Agora ja pode desplugar o aparelho do seu computador e usar normalmente"
echo "Esta versão do Palera1n foi desenvolvida por @pwnd2e e traduzida pt-BR por iTalogc iOS"
echo "A partir de agora, todas as vezes que desligar seu aparelho, coloque ele em modo DFU e faca jailbreak por este programa"
echo "Para isso, use os comandos abaixo no terminal:"
echo "cd palera1n-3.0"
echo "sudo ./palera1n.sh --tweaks sua_versao_ios"
echo "Exemplo: sudo ./palera1n.sh --tweaks 15.3.1"
echo "Divirta-se com moderacao!

} | tee logs/"$(date +%T)"-"$(date +%F)"-"$(uname)"-"$(uname -r)".log
