#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/distro.sh" ]; then
    REPO_DIR="$SCRIPT_DIR"
elif [ -f "/usr/share/nomad/lib/distro.sh" ]; then
    REPO_DIR="/usr/share/nomad"
else
    echo "Could not find Nomad´s lib/ directory next to this script or at /ust/share/nomad." >&2
    exit 1
fi
source "$REPO_DIR/lib/banner.sh"
source "$REPO_DIR/lib/distro.sh"
source "$REPO_DIR/lib/gum.sh"
source "$REPO_DIR/lib/pkg-map.sh"
source "$REPO_DIR/lib/config.sh"

nomad_banner
detect_all
ensure_gum

if ! command -v rsync &>/dev/null; then
    echo "rsync is required (used to safely exclude cache directories when copying files)."
    case "$PKG_MANAGER" in
        pacman) echo "Install it with: sudo pacman -S rsync" ;;
        apt)    echo "Install it with: sudo apt install rsync" ;;
        dnf)    echo "Install it with: sudo dnf install rsync" ;;
        zypper) echo "Install it with: sudo zypper install rsync" ;;
        *)      echo "Install rsync using your distro's package manager." ;;
    esac
    exit 1
fi

ensure_data_repo

CONF_FILE="$DATA_DIR/backup-list.conf"
PKG_DIR="$DATA_DIR/packages"
FILES_DIR="$DATA_DIR/files"
META_FILE="$DATA_DIR/.backup-meta"

nomad_banner
gum style --border rounded --padding "1 2" --border-foreground 212 \
    "Backup" "$(distro_summary)"

CROSS_DISTRO_INTENT=false
if gum confirm "Might you restore this backup on a different distro?"; then
    CROSS_DISTRO_INTENT=true
fi

BACKUP_MODE=$(gum choose --header "How do you want to back up?" \
    "Quick Backup everything, no picking" "Manual Backup: pick exactly what you want")
if [[ "$BACKUP_MODE" == Quick* ]]; then
    BACKUP_MODE="quick"
else
    BACKUP_MODE="manual"
fi

nomad_banner
gum style --foreground 212 --bold "Step 1/4: Packages"
mkdir -p "$PKG_DIR"
gum spin --spinner dot --title "Detecting installed packages..." -- sleep 0.3

pick_packages() {
    local label="$1" outfile="$2" check_coverage="${3:-false}"
    local raw
    raw=$(cat)
    if [ -z "$raw" ]; then
        : > "$outfile"
        return 0
    fi

    if [ "$BACKUP_MODE" = "quick" ]; then
        printf '%s\n' "$raw" > "$outfile"
    else
        local count
        count=$(printf '%s\n' "$raw" | wc -l)
        if gum confirm "Export all $count $label?" --affirmative "All of them" --negative "Let me pick"; then
            printf '%s\n' "$raw" > "$outfile"
        else
            printf '%s\n' "$raw" \
                | gum filter --no-limit --placeholder "type to search $label..." --height 20 \
                > "$outfile"
        fi
    fi

    if [ "$CROSS_DISTRO_INTENT" = true ] && [ "$check_coverage" = true ]; then
        check_pkg_map_coverage "$outfile" "$PKG_MANAGER" "$label"
    fi
}

case "$PKG_MANAGER" in
    pacman)
        pacman -Qqen | pick_packages "pacman packages" "$PKG_DIR/pacman.txt" true
        (pacman -Qqem 2>/dev/null || true) | pick_packages "AUR packages" "$PKG_DIR/aur.txt"
        ;;
    apt)
        apt-mark showmanual | pick_packages "apt packages" "$PKG_DIR/apt.txt" true
        ;;
    dnf)
        dnf repoquery --userinstalled --qf '%{name}' | pick_packages "dnf packages" "$PKG_DIR/dnf.txt" true
        ;;
    zypper)
        rpm -qa --qf '%{NAME}\n' | sort | pick_packages "zypper packages" "$PKG_DIR/zypper.txt" true
        ;;
    *)
        gum style --foreground 196 "Unknown package manager. Skipping package export."
        ;;
esac

if [ "$HAS_FLATPAK" = true ]; then
    flatpak list --app --columns=application | pick_packages "Flatpak apps" "$PKG_DIR/flatpak.txt"
fi

gum style --foreground 42 "✓ Package lists exported to packages/"

nomad_banner
gum style --foreground 212 --bold "Step 2/4: Files & Folders"
declare -a SELECTED=()
REUSE_ONLY=false

declare -a PRESET_PATHS=(
    "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.vimrc"
    "$HOME/.gitconfig" "$HOME/.config" "$HOME/.ssh" "$HOME/.gnupg" "$HOME/.aws"
    "$HOME/.local/share/applications" "$HOME/Desktop"
)
declare -a EXISTING_PRESETS=()
for p in "${PRESET_PATHS[@]}"; do
    [ -e "$p" ] && EXISTING_PRESETS+=("$p")
done

if [ "$BACKUP_MODE" = "quick" ]; then

    if [ -f "$CONF_FILE" ] && [ -s "$CONF_FILE" ]; then
        mapfile -t SELECTED < "$CONF_FILE"
    else
        SELECTED=("${EXISTING_PRESETS[@]}")
    fi
else

    if [ -f "$CONF_FILE" ] && [ -s "$CONF_FILE" ]; then
        COUNT=$(wc -l < "$CONF_FILE")
        CHOICE=$(gum choose --header "Found an existing backup list ($COUNT items). What do you want to do?" \
            "Reuse as-is" "Start fresh" "Add more items to it")

        if [ "$CHOICE" = "Reuse as-is" ]; then
            mapfile -t SELECTED < "$CONF_FILE"
            REUSE_ONLY=true
        elif [ "$CHOICE" = "Add more items to it" ]; then
            mapfile -t SELECTED < "$CONF_FILE"

        fi

    fi

    if [ "$REUSE_ONLY" = false ]; then
        if [ "${#EXISTING_PRESETS[@]}" -gt 0 ]; then
            mapfile -t CHOSEN_PRESETS < <(printf '%s\n' "${EXISTING_PRESETS[@]}" \
                | gum choose --no-limit --header "Select common files/folders to back up (space to select, enter to confirm)")
            SELECTED+=("${CHOSEN_PRESETS[@]}")
        fi

        while gum confirm "Add a custom file or folder to back up?"; do
            CUSTOM_PATH=$(gum file --all "$HOME" || true)
            [ -n "$CUSTOM_PATH" ] && SELECTED+=("$CUSTOM_PATH")
        done
    fi
fi

mapfile -t SELECTED < <(printf '%s\n' "${SELECTED[@]}" | sed '/^$/d' | sort -u)

if [ "${#SELECTED[@]}" -eq 0 ]; then
    gum style --foreground 214 "No files/folders selected. Only packages will be backed up."
else
    gum style --foreground 42 "✓ ${#SELECTED[@]} item(s) selected for backup"
fi

review_sensitive_dir() {
    local target="$1" label="$2"
    for i in "${!SELECTED[@]}"; do
        if [ "${SELECTED[$i]}" = "$target" ]; then
            gum style --foreground 214 --border rounded --padding "0 1" \
                "⚠ $label is selected. It may contain private keys or credentials." \
                "Worth reviewing exactly what goes in, even for a private repository."
            if gum confirm "Review $label and choose exactly which files to back up?"; then
                unset 'SELECTED[i]'
                SELECTED=("${SELECTED[@]}")
                mapfile -t SENS_FILES < <(find "$target" -maxdepth 1 -type f -printf '%f\n' | sort)
                if [ "${#SENS_FILES[@]}" -gt 0 ]; then
                    mapfile -t CHOSEN_SENS < <(printf '%s\n' "${SENS_FILES[@]}" \
                        | gum choose --no-limit --header "Select which files in $label to back up")
                    for f in "${CHOSEN_SENS[@]}"; do
                        SELECTED+=("$target/$f")
                    done
                fi
            fi
        fi
    done
}

review_sensitive_dir "$HOME/.ssh" "~/.ssh"
review_sensitive_dir "$HOME/.gnupg" "~/.gnupg"
review_sensitive_dir "$HOME/.aws" "~/.aws"

nomad_banner
gum style --foreground 212 --bold "Step 3/4: Copying"
rm -rf "$FILES_DIR"
mkdir -p "$FILES_DIR"
: > "$CONF_FILE"

RSYNC_EXCLUDES=(
    --exclude="Cache" --exclude="Cache_Data" --exclude="Code Cache"
    --exclude="GPUCache" --exclude="ShaderCache" --exclude="GrShaderCache"
    --exclude="blob_storage" --exclude="Service Worker" --exclude="IndexedDB"
    --exclude="Local Storage" --exclude="Session Storage" --exclude="CachedData"
    --exclude="component_crx_cache" --exclude="Crashpad" --exclude="*.log"
)

MAX_FILE_SIZE_MB=45
RSYNC_EXCLUDES+=(--max-size="${MAX_FILE_SIZE_MB}M")

OUTSIDE_HOME_COUNT=0
for path in "${SELECTED[@]}"; do
    [[ "$path" == "$HOME"/* ]] || OUTSIDE_HOME_COUNT=$((OUTSIDE_HOME_COUNT + 1))
done
if [ "$OUTSIDE_HOME_COUNT" -gt 0 ]; then
    gum style --foreground 214 "$OUTSIDE_HOME_COUNT item(s) are outside your home folder. Some may need root permission to read."
fi

for path in "${SELECTED[@]}"; do
    [ -e "$path" ] || continue
    if [[ "$path" == "$HOME"/* ]]; then
        rel="${path#"$HOME"}"
        dest="$FILES_DIR/home$rel"
        conf_line="HOME:$rel"
    else
        dest="$FILES_DIR/abs$path"
        conf_line="ABS:$path"
    fi

    if [ -d "$path" ]; then
        mapfile -t big_files < <(find "$path" -type f -size "+${MAX_FILE_SIZE_MB}M" 2>/dev/null)
        if [ "${#big_files[@]}" -gt 0 ]; then
            gum style --foreground 214 "Skipping ${#big_files[@]} file(s) over ${MAX_FILE_SIZE_MB}MB in $path (likely bundled app data):"
            printf '  %s\n' "${big_files[@]}"
        fi
    fi

    if (
        set -e
        mkdir -p "$(dirname "$dest")"
        if [ -d "$path" ]; then
            rsync -a "${RSYNC_EXCLUDES[@]}" "$path/" "$dest/"
        else
            cp --preserve=mode,timestamps "$path" "$dest"
        fi
    ); then
        echo "$conf_line" >> "$CONF_FILE"
    else
        gum style --foreground 196 "Could not read $path. Skipping..."
        if [[ "$path" != "$HOME"/* ]]; then
            gum style --foreground 39 "  Likely needs root. To include it yourself: sudo cp -r \"$path\" \"$dest\", then add it to $CONF_FILE manually."
        fi
    fi
done

gum style --foreground 42 "✓ Files copied into files/"

nomad_banner
gum style --foreground 212 --bold "Step 4/4: Saving to your repository"
{
    echo "last_backup=$(date -Iseconds)"
    echo "distro=$DISTRO_ID"
    echo "pkg_manager=$PKG_MANAGER"
} > "$META_FILE"

cd "$DATA_DIR"
git add -A
if git diff --cached --quiet; then
    gum style --foreground 214 "Nothing changed since last backup."
else
    git commit -m "backup: $(date '+%Y-%m-%d %H:%M:%S') on $DISTRO_ID"

    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' &>/dev/null; then
        PUSH_CMD=(git push)
    else
        PUSH_CMD=(git push -u origin main)
    fi

    stty sane 2>/dev/null; tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; tput sgr0 2>/dev/null; tput clear 2>/dev/null
    git config --global credential.helper "cache --timeout=600"
    if env GIT_TERMINAL_PROMPT=1 "${PUSH_CMD[@]}"; then
        nomad_banner
        gum style --border rounded --padding "1 2" --border-foreground 42 --bold \
            "Backup complete" "Thank you for using Nomad."
    else
        nomad_banner
        gum style --foreground 196 "Push failed. Commit is saved locally, push manually when ready."
    fi
fi