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
            echo "Checking that repository URL actually works (you may be asked to authenticate)..."
            if git ls-remote "$DATA_REPO_URL" &>/dev/null; then
                break
            else
                gum style --foreground 196 "Couldn't reach a real git repo at that URL. Check it's correct and that you have access, then try again."
            fi
        done
    fi

    save_nomad_config

    if [ ! -d "$DATA_DIR/.git" ]; then
        if git clone "$DATA_REPO_URL" "$DATA_DIR" 2>/dev/null; then
            gum style --foreground 42 "✓ Cloned existing repository into $DATA_DIR"
        else
            mkdir -p "$DATA_DIR"
            (cd "$DATA_DIR" && git init -q && git remote add origin "$DATA_REPO_URL" && git checkout -b main -q)
            gum style --foreground 42 "✓ Initialized new repository at $DATA_DIR"
        fi
    else
        current_url=$(git -C "$DATA_DIR" remote get-url origin 2>/dev/null || echo "")
        if [ "$current_url" != "$DATA_REPO_URL" ]; then
            git -C "$DATA_DIR" remote set-url origin "$DATA_REPO_URL"
            gum style --foreground 42 "✓ Updated repository remote to $DATA_REPO_URL"
        fi

        if ! git -C "$DATA_DIR" pull --ff-only origin main 2>/dev/null; then
            gum style --foreground 214 "Could not fast-forward pull. If this repo has local commits that conflict with the remote, you may need to resolve that manually in $DATA_DIR."
        fi
    fi
}
