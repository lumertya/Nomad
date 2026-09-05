#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/lib/distro.sh" ]; then
    REPO_DIR="$SCRIPT_DIR"
elif [ -f "/usr/share/nomad/lib/distro.sh" ]; then
    REPO_DIR="/usr/share/nomad"
else
    read -r -p "Nomad repository URL to clone (e.g. https://github.com/lumertya/Nomad.git): " TOOL_REPO_URL
    read -r -p "Clone into [$HOME/nomad]: " CLONE_DIR
    CLONE_DIR=${CLONE_DIR:-"$HOME/nomad"}
    
    stty sane 2>/dev/null; tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; tput sgr0 2>/dev/null; tput clear 2>/dev/null
    git config --global credential.helper "cache --timeout=600"
    if env GIT_TERMINAL_PROMPT=1 git clone "$TOOL_REPO_URL" "$CLONE_DIR"; then
        exec "$CLONE_DIR/restore.sh"
    else
        echo "Failed to clone repository"
        exit 1
    fi
fi

source "$REPO_DIR/lib/banner.sh"
source "$REPO_DIR/lib/distro.sh"
source "$REPO_DIR/lib/gum.sh"
source "$REPO_DIR/lib/pkg-map.sh"
source "$REPO_DIR/lib/config.sh"

nomad_banner
detect_all
ensure_gum
ensure_data_repo

PKG_DIR="$DATA_DIR/packages"
FILES_DIR="$DATA_DIR/files"
CONF_FILE="$DATA_DIR/backup-list.conf"
META_FILE="$DATA_DIR/.backup-meta"

nomad_banner
gum style --border rounded --padding "1 2" --border-foreground 212 \
    "Restore" "$(distro_summary)"

BACKUP_PKG_MANAGER=""
if [ -f "$META_FILE" ]; then
    source <(grep '^pkg_manager=' "$META_FILE" | sed 's/pkg_manager/BACKUP_PKG_MANAGER/')
fi

nomad_banner
gum style --foreground 212 --bold "Building restore plan..."

run_pkg_install() {
    case "$PKG_MANAGER" in
        pacman) sudo pacman -S --needed --noconfirm "$@" ;;
        apt)    sudo apt install -y "$@" ;;
        dnf)    sudo dnf install -y "$@" ;;
        zypper) sudo zypper install -y "$@" ;;
        *) return 1 ;;
    esac
}

install_pkg_array() {
    local label="$1"; shift
    local pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return 0

    if ! run_pkg_install "${pkgs[@]}"; then
        gum style --foreground 214 "Batch install of $label hit a problem. Retrying one at a time so a single bad package doesn't block the rest."
        declare -a failed=()
        for p in "${pkgs[@]}"; do
            run_pkg_install "$p" || failed+=("$p")
        done
        if [ "${#failed[@]}" -gt 0 ]; then
            gum style --foreground 196 "Could not install ${#failed[@]} $label package(s):"
            printf '  %s\n' "${failed[@]}"
        fi
    fi
}

install_pkg_file() {
    local label="$1" file="$2"
    [ -s "$file" ] || return 0
    mapfile -t pkgs < "$file"
    install_pkg_array "$label" "${pkgs[@]}"
}

install_aur_array() {
    local pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return 0
    if ! "$AUR_HELPER" -S --needed --noconfirm "${pkgs[@]}"; then
        gum style --foreground 214 "Batch AUR install hit a problem. Retrying one at a time."
        declare -a failed=()
        for p in "${pkgs[@]}"; do
            "$AUR_HELPER" -S --needed --noconfirm "$p" || failed+=("$p")
        done
        if [ "${#failed[@]}" -gt 0 ]; then
            gum style --foreground 196 "Could not install ${#failed[@]} AUR package(s):"
            printf '  %s\n' "${failed[@]}"
        fi
    fi
}

PLAN_PKG_MODE="none"
declare -a PLAN_SAME_PKGS=()
declare -a PLAN_AUR_PKGS=()
declare -a PLAN_TRANSLATED=()
declare -a PLAN_UNMATCHED=()

    if [ -z "$BACKUP_PKG_MANAGER" ] || [ "$BACKUP_PKG_MANAGER" = "$PKG_MANAGER" ]; then
        case "$PKG_MANAGER" in
            pacman)
                [ -f "$PKG_DIR/pacman.txt" ] && mapfile -t PLAN_SAME_PKGS < "$PKG_DIR/pacman.txt"
                [ -s "$PKG_DIR/aur.txt" ] && mapfile -t PLAN_AUR_PKGS < "$PKG_DIR/aur.txt"
                ;;
            apt) [ -f "$PKG_DIR/apt.txt" ] && mapfile -t PLAN_SAME_PKGS < "$PKG_DIR/apt.txt" ;;
            dnf) [ -f "$PKG_DIR/dnf.txt" ] && mapfile -t PLAN_SAME_PKGS < "$PKG_DIR/dnf.txt" ;;
            zypper) [ -f "$PKG_DIR/zypper.txt" ] && mapfile -t PLAN_SAME_PKGS < "$PKG_DIR/zypper.txt" ;;
            *) PLAN_PKG_MODE="none" ;;
        esac
    elif [ "$PKG_MANAGER" != "unknown" ]; then
        PLAN_PKG_MODE="cross"
        SOURCE_FILE="$PKG_DIR/$BACKUP_PKG_MANAGER.txt"
        if [ -f "$SOURCE_FILE" ]; then
            while IFS= read -r pkg; do
                [ -z "$pkg" ] && continue
                if result=$(translate_package "$pkg" "$BACKUP_PKG_MANAGER" "$PKG_MANAGER"); then
                    PLAN_TRANSLATED+=("$result")
                else
                    PLAN_UNMATCHED+=("$pkg")
                fi
            done < "$SOURCE_FILE"
        fi
    fi

declare -a PLAN_FLATPAKS=()
[ -s "$PKG_DIR/flatpak.txt" ] && mapfile -t PLAN_FLATPAKS < "$PKG_DIR/flatpak.txt"

ABS_COUNT=$(grep -c '^ABS:' "$CONF_FILE" 2>/dev/null || echo 0)
HOME_COUNT=$(grep -c '^HOME:' "$CONF_FILE" 2>/dev/null || echo 0)

echo "This restore will do the following:"
echo

if [ "$PLAN_PKG_MODE" = "same" ]; then
    echo "Packages: ${#PLAN_SAME_PKGS[@]} via $PKG_MANAGER"
    if [ "${#PLAN_AUR_PKGS[@]}" -gt 0 ]; then
        if [ "$HAS_AUR_HELPER" = true ]; then
            echo "AUR packages: ${#PLAN_AUR_PKGS[@]} via $AUR_HELPER"
        else
            echo "AUR packages: ${#PLAN_AUR_PKGS[@]} found, but no yay/paru installed. These will be skipped"
        fi
    fi
elif [ "$PLAN_PKG_MODE" = "cross" ]; then
    echo "Packages: backup was made on $BACKUP_PKG_MANAGER, restoring on $PKG_MANAGER"
    echo "${#PLAN_TRANSLATED[@]} translated and ready to install, ${#PLAN_UNMATCHED[@]} with no known translation (manual install needed)"
    if [ "$BACKUP_PKG_MANAGER" = "pacman" ] && [ -s "$PKG_DIR/aur.txt" ]; then
        echo "AUR packages from the backup don't carry over cross-distro. Will need manual equivalents"
    fi
else
    echo "Packages: none to install"
fi

echo "Flatpak apps: ${#PLAN_FLATPAKS[@]}"

echo "Files/folders: $((HOME_COUNT + ABS_COUNT)) total"
if [ "$ABS_COUNT" -gt 0 ]; then
    echo "$ABS_COUNT outside your home folder. Will need root permission"
fi

if [ -s "$CONF_FILE" ]; then
    echo
    echo "The following will be restored:"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        kind="${line%%:*}"
        rel="${line#*:}"
        if [ "$kind" = "HOME" ]; then
            preview_dest="$HOME$rel"
        else
            preview_dest="$rel"
        fi
        if [ -e "$preview_dest" ]; then
            echo "$preview_dest (already exists. Will be moved aside first)"
        else
            echo "$preview_dest"
        fi
    done < "$CONF_FILE"
fi

echo

if [ "$PLAN_PKG_MODE" = "none" ] && [ "${#PLAN_FLATPAKS[@]}" -eq 0 ] && [ ! -s "$CONF_FILE" ]; then
    gum style --foreground 214 "Nothing to restore. No packages, Flatpak apps, or files were found in this backup."
    exit 0
fi

if ! gum confirm "Proceed with this restore?"; then
    gum style --foreground 214 "Nothing was changed."
    exit 0
fi

nomad_banner
gum style --foreground 212 --bold "Step 1/3: Packages"
[ "$PKG_MANAGER" = "apt" ] && sudo apt update

if [ "$PLAN_PKG_MODE" = "same" ]; then
    install_pkg_array "$PKG_MANAGER" "${PLAN_SAME_PKGS[@]}"
    if [ "${#PLAN_AUR_PKGS[@]}" -gt 0 ]; then
        if [ "$HAS_AUR_HELPER" = true ]; then
            install_aur_array "${PLAN_AUR_PKGS[@]}"
        else
            gum style --foreground 214 "AUR packages found but no yay/paru installed. Skipping (install an AUR helper and rerun to catch these)."
        fi
    fi
elif [ "$PLAN_PKG_MODE" = "cross" ]; then
    install_pkg_array "translated" "${PLAN_TRANSLATED[@]}"
    if [ "${#PLAN_UNMATCHED[@]}" -gt 0 ]; then
        gum style --foreground 214 \
            "No known translation for ${#PLAN_UNMATCHED[@]} package(s). Search for the $DISTRO_ID equivalent of each, then install with: $(manual_install_syntax)"
        printf '  %s\n' "${PLAN_UNMATCHED[@]}"
    fi
    if [ "$BACKUP_PKG_MANAGER" = "pacman" ] && [ -s "$PKG_DIR/aur.txt" ]; then
        gum style --foreground 214 "AUR packages from the backup aren't restored on a different distro. Search for each on $DISTRO_ID and install with: $(manual_install_syntax)"
    fi
fi
gum style --foreground 42 "✓ Packages done"

nomad_banner
gum style --foreground 212 --bold "Step 2/3: Flatpak"
if [ "${#PLAN_FLATPAKS[@]}" -gt 0 ]; then
    if ! command -v flatpak &>/dev/null; then
        if gum confirm "Flatpak isn't installed. Install it now?"; then
            case "$PKG_MANAGER" in
                pacman) sudo pacman -S --needed --noconfirm flatpak ;;
                apt)    sudo apt install -y flatpak ;;
                dnf)    sudo dnf install -y flatpak ;;
                zypper) sudo zypper install -y flatpak ;;
            esac
        fi
    fi
    if command -v flatpak &>/dev/null; then
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        for app in "${PLAN_FLATPAKS[@]}"; do
            flatpak install -y flathub "$app" || gum style --foreground 214 "Could not install $app. May not be on Flathub, skipping."
        done
        gum style --foreground 42 "✓ Flatpak apps installed"
    fi
else
    gum style --foreground 214 "No Flatpak apps to restore."
fi

nomad_banner
gum style --foreground 212 --bold "Step 3/3: Files & Folders"
if [ -s "$CONF_FILE" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        kind="${line%%:*}"
        rel="${line#*:}"
        if [ "$kind" = "HOME" ]; then
            src="$FILES_DIR/home$rel"
            dest="$HOME$rel"
            SUDO=""
        else
            src="$FILES_DIR/abs$rel"
            dest="$rel"
            SUDO="sudo"
        fi
        [ -e "$src" ] || continue

        if ! (
            set -e
            if [ -e "$dest" ]; then
                backup_dest="${dest}.bak.$(date +%Y%m%d%H%M%S)"
                $SUDO mv "$dest" "$backup_dest"
                gum style --foreground 214 "Existing $dest moved to $backup_dest"
            fi
            $SUDO mkdir -p "$(dirname "$dest")"
            $SUDO cp -r --preserve=mode,timestamps "$src" "$dest"
        ); then
            if [ "$kind" = "ABS" ]; then
                gum style --foreground 196 "Could not restore $dest. It likely needs root permission you don't have here."
                gum style --foreground 39 "  To do it yourself: sudo cp -r \"$src\" \"$dest\""
            else
                gum style --foreground 196 "Could not restore $dest. Skipping..."
            fi
            continue
        fi
        echo "Restored: $dest"
    done < "$CONF_FILE"

    declare -a SENSITIVE_DIRS=("$HOME/.ssh" "$HOME/.gnupg" "$HOME/.aws")
    declare -a DIRS_TO_FIX=()
    for d in "${SENSITIVE_DIRS[@]}"; do
        [ -d "$d" ] && DIRS_TO_FIX+=("$d")
    done

    if [ "${#DIRS_TO_FIX[@]}" -gt 0 ]; then
        gum style --foreground 214 \
            "Found sensitive directories that may need permission fixes: ${DIRS_TO_FIX[*]}" \
            "Will run: chmod 700 on each directory, chmod 600 on its files (644 for *.pub / known_hosts)."
        if gum confirm "Reset their permissions to these standard secure defaults?"; then
            for d in "${DIRS_TO_FIX[@]}"; do
                chmod 700 "$d"
                find "$d" -maxdepth 1 -type f | while read -r f; do
                    case "$(basename "$f")" in
                        *.pub|known_hosts|known_hosts.old) chmod 644 "$f" ;;
                        *) chmod 600 "$f" ;;
                    esac
                done
                gum style --foreground 42 "✓ Fixed permissions on $d"
            done
        fi
    fi

    gum style --foreground 42 "✓ Files restored (any conflicts backed up with .bak.<timestamp>)"
else
    gum style --foreground 214 "No files/folders to restore."
fi

nomad_banner
gum style --border rounded --padding "1 2" --border-foreground 42 --bold \
    "Restore complete" "You may need to log out/in for shell configs and PATH changes to take effect." "Thank you for using Nomad."