ensure_gum() {
    if command -v gum &>/dev/null; then
        return 0
    fi

    echo "gum is required to run this tool."
    case "$PKG_MANAGER" in
        pacman)
            echo "Install it with: sudo pacman -S gum"
            ;;
        dnf)
            echo "Install it with: sudo dnf install gum"
            ;;
        zypper)
            echo "Install it with: sudo zypper install gum"
            ;;
        apt)
            echo "Install it with:"
            echo "  sudo mkdir -p /etc/apt/keyrings"
            echo "  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg"
            echo '  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list'
            echo "  sudo apt update && sudo apt install gum"
            ;;
        *)
            echo "Search 'charmbracelet gum install' for instructions for your system."
            ;;
    esac
    exit 1
}
