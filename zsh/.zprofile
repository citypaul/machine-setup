# Login shells: macOS runs /etc/zprofile (path_helper) after .zshenv and moves system directories
# such as /usr/local/bin back in front of ours, so a preinstalled node would shadow mise's.
# Put mise shims and ~/.local/bin back in front (plan.md §4.5, ADR 0001 F-20).
typeset -U path
path=("$HOME/.local/share/mise/shims" "$HOME/.local/bin" $path)
export PATH
