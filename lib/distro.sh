detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_ID_LIKE=""
    fi
    export DISTRO_ID DISTRO_ID_LIKE
}

detect_pkg_manager() {
    if command -v pacman &>/dev/null && [ -d /var/lib/pacman ]; then
        PKG_MANAGER="pacman"
    elif command -v apt &>/dev/null && [ -d /var/lib/dpkg ]; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null && [ -d /var/lib/rpm ]; then
        PKG_MANAGER="dnf"
    elif command -v zypper &>/dev/null && [ -d /var/lib/rpm ]; then
        PKG_MANAGER="zypper"
    else
        PKG_MANAGER="unknown"
    fi
    export PKG_MANAGER
}

detect_foreign_pkg_managers() {
    local foreign=()
    for pm in pacman apt dnf zypper; do
        if [ "$pm" != "$PKG_MANAGER" ] && command -v "$pm" &>/dev/null; then
            foreign+=("$pm")
        fi
    done

    if [ "${#foreign[@]}" -gt 0 ]; then
        gum style --foreground 214 --border rounded --padding "0 1" \
            "⚠ Found package manager binary(ies) that don't belong to $DISTRO_ID: ${foreign[*]}" \
            "These aren't managing your system and can likely be removed."
    fi
}

detect_aur_helper() {
    HAS_AUR_HELPER=false
    AUR_HELPER=""
    if [ "$PKG_MANAGER" = "pacman" ]; then
        if command -v yay &>/dev/null; then
            HAS_AUR_HELPER=true
            AUR_HELPER="yay"
        elif command -v paru &>/dev/null; then
            HAS_AUR_HELPER=true
            AUR_HELPER="paru"
        fi
    fi
    export HAS_AUR_HELPER AUR_HELPER
}

detect_flatpak() {
    if command -v flatpak &>/dev/null; then
        HAS_FLATPAK=true
    else
        HAS_FLATPAK=false
    fi
    export HAS_FLATPAK
}

detect_all() {
    detect_distro
    detect_pkg_manager
    detect_foreign_pkg_managers
    detect_aur_helper
    detect_flatpak
}

distro_summary() {
    echo "Distro: ${DISTRO_ID}  |  Package manager: ${PKG_MANAGER}  |  AUR helper: ${AUR_HELPER:-none}  |  Flatpak: ${HAS_FLATPAK}"
}

manual_install_syntax() {
    case "$PKG_MANAGER" in
        pacman) echo "sudo pacman -S <package>" ;;
        apt)    echo "sudo apt install <package>" ;;
        dnf)    echo "sudo dnf install <package>" ;;
        zypper) echo "sudo zypper install <package>" ;;
        *)      echo "(install command for $PKG_MANAGER unknown)" ;;
    esac
}
