translate_package() {
    local pkg="$1" from="$2" to="$3"
    local map_file="$REPO_DIR/lib/pkg-map.txt"
    [ -f "$map_file" ] || return 1

    local from_col to_col
    case "$from" in
        pacman) from_col=1 ;; apt) from_col=2 ;; dnf) from_col=3 ;; zypper) from_col=4 ;;
        *) return 1 ;;
    esac
    case "$to" in
        pacman) to_col=1 ;; apt) to_col=2 ;; dnf) to_col=3 ;; zypper) to_col=4 ;;
        *) return 1 ;;
    esac

    while IFS=':' read -r canonical c1 c2 c3 c4; do
        [[ "$canonical" == \#* || -z "$canonical" ]] && continue
        local cols=("$c1" "$c2" "$c3" "$c4")
        local from_val="${cols[$((from_col - 1))]}"
        local to_val="${cols[$((to_col - 1))]}"
        if [ "$from_val" = "$pkg" ] && [ -n "$to_val" ]; then
            echo "$to_val"
            return 0
        fi
    done < "$map_file"

    return 1
}

check_pkg_map_coverage() {
    local file="$1" manager="$2" label="$3"
    [ -s "$file" ] || return 0
    local map_file="$REPO_DIR/lib/pkg-map.txt"
    [ -f "$map_file" ] || return 0

    local col
    case "$manager" in
        pacman) col=2 ;; apt) col=3 ;; dnf) col=4 ;; zypper) col=5 ;;
        *) return 0 ;;
    esac

    local total=0 matched=0
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        total=$((total + 1))
        if awk -F: -v c="$col" -v p="$pkg" \
            '$1 !~ /^#/ && $1 != "" && $c == p { found=1 } END { exit !found }' \
            "$map_file"; then
            matched=$((matched + 1))
        fi
    done < "$file"

    [ "$total" -eq 0 ] && return 0
    gum style --foreground 39 "$label: $matched of $total have a known cross-distro match"
}
