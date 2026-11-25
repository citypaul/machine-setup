# Antigravity desktop and CLI

[Back to the README](../README.md)

Both profiles install the Antigravity CLI (`agy`) as a native mise tool on
macOS and Linux. On macOS, the `desktop` role also installs the
[Antigravity app](https://formulae.brew.sh/cask/antigravity) through mise's cask
manager in `/Applications/Antigravity.app`. Installing both requires macOS 13
or later.
The app manages agent conversations and projects visually; `agy` runs an agent
in the current project directory from your terminal. These are separate
packages from Antigravity IDE. See Google's [getting started guide](https://antigravity.google/docs/getting-started).

On a machine that is already set up, get the newest machine-setup and apply it:

```bash
machine-setup self-update
machine-setup converge --role desktop
```

To install just these two from an existing setup whose mise dotfiles are
already linked to a checkout containing this change:

```bash
cd ~/personal/machine-setup   # or the checkout printed by machine-setup --version
~/.local/bin/mise bootstrap packages apply brew-cask:antigravity --yes
~/.local/bin/mise install http:antigravity-cli
agy --version
open -a Antigravity
```

Sign in when prompted in the app. For the CLI, change to your project directory
and run `agy`, then complete its terminal setup, workspace trust and sign-in
prompts. Authentication stays on the machine; this repo supplies no credentials
or Antigravity settings.

Later, `machine-setup update` upgrades the desktop package and CLI tool through
mise. The CLI declaration discovers releases from Google's manifest, verifies
the download against its SHA-512 checksum, and exposes `agy` through mise's
PATH and shims. `AGY_CLI_DISABLE_AUTO_UPDATE=true` keeps CLI updates under mise;
use `machine-setup update` rather than `agy update`. The desktop app can also
update itself. Re-running converge installs missing packages and tools.

The CLI uses mise's HTTP backend because the pinned mise version installs the
CLI cask's wrapper without retaining the executable it launches. The release
feed includes Google's build id in the mise version. On Linux this installs
the CLI only; the desktop app is not managed here yet.
