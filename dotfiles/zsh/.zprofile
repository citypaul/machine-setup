# Login shells: macOS runs /etc/zprofile (path_helper) after .zshenv and moves system directories
# such as /usr/local/bin back in front of ours, so a preinstalled node would shadow mise's.
# Put mise shims, ~/.local/bin and the Homebrew prefix back in front (plan.md §4.5, ADR 0001 F-20).
typeset -U path
for _machine_setup_dir in /home/linuxbrew/.linuxbrew/sbin /home/linuxbrew/.linuxbrew/bin /opt/homebrew/sbin /opt/homebrew/bin; do
  [[ -d "$_machine_setup_dir" ]] && path=("$_machine_setup_dir" $path)
done
unset _machine_setup_dir
path=("$HOME/.local/share/mise/shims" "$HOME/.local/bin" $path)
export PATH
