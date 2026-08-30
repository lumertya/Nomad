# Nomad

Nomad backs up your installed packages, Flatpak apps, and any files/folders you choose, then restores all of it on a fresh install, even on a different distro. It's built as two separate pieces: the tool itself (this repository, open source) and your personal backup data (your own separate, private repository, never mixed with the tool's code).

Supports Arch (pacman + AUR), Debian/Ubuntu (apt), Fedora (dnf), and openSUSE (zypper), plus Flatpak everywhere.

## Why nomad?

While backing up files and packages manually with git already covers most of this, Nomad adds several things on top. For users who move between Arch, Debian, Fedora, and openSUSE, Nomad maps common package names across package managers, though users who remain on a single distro won't benefit from this. Git tracks only the executable bit, not full permission modes, so SSH and GPG keys can be restored with incorrect permissions and rejected by the tools that require them; Nomad resets affected files to standard secure defaults, displaying the exact commands before execution. Installed packages and configuration files can be searched and selected interactively, rather than assembled manually with find and cp. And restoring works with a single command across every supported distro, which is most useful for users who rebuild systems or switch distros with some regularity.

For users who do not require these features, backing things up manually remains a simpler and equally valid approach.

## What's backed up

Nomad backs up your installed packages, exported in the correct format for your distro's package manager, along with AUR packages on Arch if yay or paru is installed, and Flatpak apps regardless of distro. It also backs up any files and folders you choose, stored in a way that lets them be restored even under a different username or on a different machine, plus your selections and backup history so future backups and restores can pick up where you left off.

You'll need a private git repository of your own to store this data in, separate from the nomad tool repo. Nomad will prompt you to create or connect one the first time you run backup.sh or restore.sh. This repo must be set to private, since it can contain real credentials such as SSH keys or tokens if you choose to back those up.

## What's NOT backed up

Databases, game saves, and individual app settings aren't included unless you explicitly select them during the file/folder picker step.

## Setup (first time)

Clone this repository, then:

```bash
cd nomad
chmod +x backup.sh restore.sh
```

The first time you run backup.sh or restore.sh, nomad will ask for a local folder and the URL of a private git repository to store your backup data in, separate from this tool repository. That pairing is saved locally at `~/.config/nomad/config` and is never committed anywhere.

## Connecting your private repository

Nomad needs to authenticate with your private repository, either via SSH or HTTPS. Pick based on the machine you're on.

An SSH key is best for a machine you'll use long-term, since once it's set up it never asks for credentials again. Generate one with `ssh-keygen -t ed25519 -C "nomad"`, add the public key (found with `cat ~/.ssh/id_ed25519.pub`) to GitHub under Settings, SSH and GPG keys, New SSH key, then use the `git@github.com:you/your-private-repository.git` URL format when nomad asks for your repository.

HTTPS with a Personal Access Token is best for a brand-new machine, like right after restore.sh on a fresh install, since there's no key to set up first. On GitHub, go to Settings, Developer settings, Personal access tokens, Tokens (classic), and generate a new token with the repo scope checked. Use the `https://github.com/you/your-private-repository.git` URL format when nomad asks for your repo, and when prompted for a password, paste the token rather than your actual GitHub password. Optionally, run `git config --global credential.helper store` once so you're not asked for the token on every single backup or restore.

## Backing up

```bash
./backup.sh
```

This asks whether the backup might ever be restored on a different distro, then asks whether you want a Quick Backup with everything and no picking, or a Manual Backup where you choose exactly what to include. It detects your distro and package manager and exports your installed packages and Flatpaks. In Manual mode, it walks you through picking files and folders with a gum-powered picker; common configs like `.bashrc`, `.config`, `.ssh`, `.gnupg`, and `.aws` are offered automatically if they exist, and you can add anything custom. If `.ssh`, `.gnupg`, or `.aws` were selected, it offers to review and hand-pick exactly which files inside go into the backup. Finally, it copies everything into your private repo, commits, and pushes.

Run it again any time. It remembers your file/folder selections and lets you reuse, extend, or start fresh.

## Restoring on a new PC

Clone this repository and run:

```bash
cd nomad
./restore.sh
```

Or, without cloning first:

```bash
curl -o restore.sh https://raw.githubusercontent.com/lumertya/nomad/main/restore.sh
chmod +x restore.sh
./restore.sh
```

This clones your private repository, or asks for it if this is a new machine, then detects the new machine's distro and package manager. It reinstalls packages using the correct package manager for this machine, translating package names via `lib/pkg-map.txt` if you're restoring on a different distro than you backed up from, and reinstalls Flatpak apps via Flathub. It then shows you exactly what will be restored and where, and once confirmed, restores your chosen files and folders to their original locations; anything already at the destination is moved aside rather than overwritten. Finally, it resets permissions on `~/.ssh`, `~/.gnupg`, and `~/.aws` to standard secure defaults if they were restored, showing the exact commands and asking for confirmation first.

## Notes

Gum is required for the interactive picker, and both scripts will tell you if it's missing rather than install it for you. Package restore works best when restoring to the same distro family you backed up from, since cross-distro package name mismatches mean full package restore isn't guaranteed. A best-effort translation table covers common packages across pacman, apt, dnf, and zypper, and anything outside that list is listed with the correct install command syntax for your distro so you can search for the equivalent package name and install it yourself. Flatpak apps restore consistently across all distros, since Flatpak isn't tied to any specific package manager. On openSUSE, the package list includes all installed packages rather than just explicitly-installed ones, since zypper doesn't have as straightforward a way to filter dependencies out as the others do. Restored config files are copied byte-for-byte to their original location; most user-level files are portable across distros by nature, though application configs that reference distro-specific paths or options aren't validated and may need manual review after a cross-distro restore. AUR packages only restore if you already have yay or paru installed on the new machine, and they don't carry over on a cross-distro restore. Flatpak restore assumes apps came from Flathub, and anything from a different remote will fail to install and get skipped with a warning. Files or folders outside your home directory need root permission to back up or restore; nomad will tell you how many and, if one fails, give you the exact manual command to run yourself, and it never attempts to escalate permissions on its own. Since the backed-up files mirror paths relative to your home directory, restoring works even if your username differs between the old and new machine.

## Security & Trust

Nomad is plain bash. No compiled binaries, nothing hidden. Every line is readable before you run it.

Nomad never sees, stores, or transmits your git or GitHub credentials. When git push or git clone needs a username, password, SSH passphrase, or token, that prompt comes directly from git itself talking to your terminal. Nomad only launches git as a subprocess and checks whether it succeeded, and there is no code path in nomad that reads, logs, or forwards anything you type into that prompt.

If you don't take that on faith, check it yourself by running `grep -rniE "password|credential|token|secret" backup.sh restore.sh lib/*.sh`. Every match will be a warning message nomad prints to you, never code that reads one. The only network calls anywhere in the tool are git itself, flatpak remote-add pointing at Flathub's own public repo, and gum's own install commands from Charm's official repo, all fully visible in the source.

## License

MIT, see [LICENSE](LICENSE).
