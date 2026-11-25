# Taking over a machine that Stow manages

[Back to the README](../README.md)

The same command takes over a machine whose dotfiles are GNU Stow links into
`~/.dotfiles`, such as Paul's MacBook Pro:

```bash
cd ~/personal/machine-setup && git pull
./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine personal-macbook --dry-run   # see everything first; changes nothing
./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine personal-macbook             # do it; asks once before migrating
```

When a top-level dotfile or an entry in `~/.config` links into the Stow dir,
bootstrap, before it converges:

1. Lists the packages the removal allowlist would remove from this machine.
2. Runs the migration's dry run (`tasks/migrate --dry-run`). A real file where
   a link should go stops the run here, with nothing changed; the message
   gives the `tasks/migrate --force` command that saves the file in the
   journal and replaces it.
3. Asks once at a terminal (`--yes` skips the question), then migrates. Every
   write is journaled under `~/.local/state/machine-setup/migration/`, and any
   failure part-way rolls the home directory back exactly.
4. Converges as usual, then runs `check-machine`.

Before you start on a Mac you already use (learned taking over the MacBook
Pro, ADR 0001 F-64):

- **Back up.** The dotfile migration rolls back; the converge after it
  (packages, the Dock, the Claude settings merge) does not.
- **Carry over what the repo's files replace.** Move your own hosts from
  `~/.ssh/config` into `~/.ssh/config.d/` (any file name), your machine's git
  settings (signing key, `git-lfs` filters, extra aliases) into
  `~/.gitconfig.local`, and your own shell lines into `~/.zshrc.local`. The
  repo's files include all three and never write to them.
- **Delete an App Store copy of Slack**: the desktop role installs the cask.
- **Decide about the system update.** A first install upgrades every Homebrew
  package and runs Apple's updates. To skip that on a Mac that is already in
  use, pass `--skip-system-update`, and afterwards write the marker by hand so
  a later converge does not run it either:
  `date -u +%FT%TZ > ~/.local/state/machine-setup/system-updated`.
- **Run the `--dry-run` first.** It lists every real file that sits where the
  repo wants a link or a rendered file. `tasks/migrate --force` saves those in
  the journal and replaces them; run bootstrap again afterwards.

On macOS, allow the terminal to read the Desktop folder if asked: the
migration waits for that answer (ADR 0001 F-47). It runs once; later runs only
converge. `~/.dotfiles` is not touched, so remove it once you are happy.
`--stow-dir` names a Stow dir kept somewhere else.

## Rehearsing the migration on a VM

Run this on the macOS VM before touching a real Mac. Snapshot the VM after
step 2 so the rehearsal can be repeated. Steps 1 and 2 recreate the old
setup the way it is on Paul's Mac: Oh My Zsh as a real checkout, and only the
eight Stow packages that are live there, not everything `./install.sh` stows.

1. Install the Command Line Tools (a dialog opens; wait for it to finish),
   then Homebrew, then Stow and Oh My Zsh:

   ```bash
   xcode-select --install
   ```

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

   ```bash
   brew install stow && git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
   ```

2. Clone the old dotfiles and stow the live packages:

   ```bash
   git clone https://github.com/citypaul/.dotfiles ~/.dotfiles && cd ~/.dotfiles && stow zsh tmux gnupg alacritty zellij .oh-my-zsh ghostty herdr
   ```

3. Clone this repo to `~/machine-setup`, save the selection, and install the
   pinned mise (the selection step installs nothing):

   ```bash
   git clone https://github.com/citypaul/machine-setup ~/machine-setup
   ```

   ```bash
   cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --profile personal --role desktop --machine vm --select-only --yes
   ```

   ```bash
   curl -fsSL https://mise.run | MISE_VERSION=$(sed -n 's/^MISE_PIN="\(.*\)"$/\1/p' ~/machine-setup/bootstrap.sh) MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh
   ```

4. Dry run, then the migration, then a converge and `check-machine`:

   ```bash
   cd ~/machine-setup && tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles --dry-run
   ```

   ```bash
   cd ~/machine-setup && tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles
   ```

   ```bash
   cd ~/machine-setup && ./bootstrap.sh --dir "$PWD" --yes && ~/.local/bin/mise run check-machine
   ```

5. Restore the snapshot and rehearse a failure: the run must roll back and
   leave every file and link as it was.

   ```bash
   cd ~/machine-setup && MACHINE_SETUP_MIGRATE_FAIL_AT=verify tasks/migrate --checkout "$PWD" --stow-dir ~/.dotfiles
   ```
