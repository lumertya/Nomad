NOMAD_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nomad"
NOMAD_CONFIG_FILE="$NOMAD_CONFIG_DIR/config"

load_nomad_config() {
    DATA_DIR=""
    DATA_REPO_URL=""
    if [ -f "$NOMAD_CONFIG_FILE" ]; then
        source "$NOMAD_CONFIG_FILE"
    fi
}

save_nomad_config() {
    mkdir -p "$NOMAD_CONFIG_DIR"
    {
        echo "DATA_DIR=$DATA_DIR"
        echo "DATA_REPO_URL=$DATA_REPO_URL"
    } > "$NOMAD_CONFIG_FILE"
}

ensure_data_repo() {
    load_nomad_config

    stty sane 2>/dev/null; tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; tput sgr0 2>/dev/null; tput clear 2>/dev/null
    git config --global credential.helper "cache --timeout=600"

    if [ -n "$DATA_DIR" ] && [ -n "$DATA_REPO_URL" ]; then
        CHOICE=$(gum choose --header "Data repo: $DATA_REPO_URL ($DATA_DIR). What do you want to do?" \
            "Keep using this" "Change it")
        if [ "$CHOICE" = "Change it" ]; then
            DATA_DIR=""
            DATA_REPO_URL=""
        fi
    fi

    if [ -z "$DATA_DIR" ] || [ -z "$DATA_REPO_URL" ]; then
        gum style --foreground 214 --border rounded --padding "0 1" \
            "Nomad keeps your backup data in its own repository, separate from the tool itself." \
            "Make sure that your repository is set to PRIVATE on GitHub since it can contain real credentials."
    fi

    if [ -z "$DATA_DIR" ]; then
        DATA_DIR=$(gum input --value "${DATA_DIR:-$HOME/nomad-data}" --header "Local folder to store your backup data in")
        [ -z "$DATA_DIR" ] && DATA_DIR="$HOME/nomad-data"
    fi

    if [ -z "$DATA_REPO_URL" ]; then
        while true; do
            DATA_REPO_URL=$(gum input --placeholder "git@github.com:you/nomad-data-private.git" \
                --header "URL of your PRIVATE data repo (required). Use the git@ SSH form, not https://")
            if [ -z "$DATA_REPO_URL" ]; then
                gum style --foreground 196 "A repo URL is required. Nomad has nowhere to push your backup without one."
                continue
            fi

            echo "Checking if that repository URL actually works (you may be asked to authenticate)..."
            CLONE_ERR=$(mktemp)
            stty sane 2>/dev/null; tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; tput sgr0 2>/dev/null; tput clear 2>/dev/null
            git config --global credential.helper "cache --timeout=600"
            if env GIT_TERMINAL_PROMPT=1 git clone "$DATA_REPO_URL" "$DATA_DIR" 2>"$CLONE_ERR"; then
                gum style --foreground 42 "✓ Connected to $DATA_REPO_URL"
                rm -f "$CLONE_ERR"
                break
            else
                gum style --foreground 196 "Couldn´t reach a real repository at that URL. Check it's correct and that you have access, then try again."
                cat "$CLONE_ERR" >&2
                rm -f "$CLONE_ERR"
                rm -rf "$DATA_DIR"
                DATA_REPO_URL=""
            fi
        done
        save_nomad_config
    else    
        save_nomad_config
        if [ ! -d "$DATA_DIR/.git" ]; then
            echo "Connecting to your data repository (you may be asked to authenticate)..."
            if env GIT_TERMINAL_PROMPT=1 git clone "$DATA_REPO_URL" "$DATA_DIR"; then
                gum style --foreground 42 "✓ Connected to $DATA_REPO_URL"
            else
                gum style --foreground 196 "Couldn't reach $DATA_REPO_URL. Check your connection and access, then run Nomad again."
                exit 1
            fi
        else
            current_url=$(git -C "$DATA_DIR" remote get-url origin 2>/dev/null || echo "")
            if [ "$current_url" != "$DATA_REPO_URL" ]; then
                git -C "$DATA_DIR" remote set-url origin "$DATA_REPO_URL"
                gum style --foreground 42 "✓ Updated repository remote to $DATA_REPO_URL"
            fi

            if ! env GIT_TERMINAL_PROMPT=1 git -C "$DATA_DIR" pull --ff-only origin main 2>/dev/null; then
                gum style --foreground 214 "Could not fast-forward pull. If this repository has local commits that conflict with the remote, you may need to resolve that manually in $DATA_DIR."
            fi
        fi
    fi

}
