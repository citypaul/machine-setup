# Read by every zsh, including non-interactive `ssh host cmd` and cron jobs. Exposes mise shims,
# ~/.local/bin and the Homebrew prefix so mise-managed runtimes and brewed CLI tools resolve without
# an interactive shell (plan.md §4.5). The prefix is added by existence, not by a `brew` binary:
# on Linux mise pours bottles without Homebrew itself.
typeset -U path
for _machine_setup_dir in /home/linuxbrew/.linuxbrew/sbin /home/linuxbrew/.linuxbrew/bin /opt/homebrew/sbin /opt/homebrew/bin; do
  [[ -d "$_machine_setup_dir" ]] && path=("$_machine_setup_dir" $path)
done
unset _machine_setup_dir
path=("$HOME/.local/share/mise/shims" "$HOME/.local/bin" $path)
export PATH
