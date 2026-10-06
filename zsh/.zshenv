# Read by every zsh, including non-interactive `ssh host cmd` and cron jobs. Exposes mise shims and
# ~/.local/bin so mise-managed runtimes resolve without an interactive shell (plan.md §4.5).
typeset -U path
path=("$HOME/.local/share/mise/shims" "$HOME/.local/bin" $path)
export PATH
