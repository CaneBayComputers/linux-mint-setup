# linux-mint-setup

Scripts for setting up customer Linux Mint machines.

`setup.sh` takes a fresh Mint install and makes it ready to hand over:

- Points APT at fast mirrors (Mint → `fastly.linuxmint.io`, Ubuntu base → `mirror.nodesdirect.com`)
- Purges the stock apps we don't want (Firefox, Thunderbird, Hexchat, Timeshift, etc.)
- Disables services and timers the customer doesn't need
- Turns off Cinnamon's Night Light filter
- Turns on Update Manager's automatic updates and obsolete-kernel cleanup

Removing LibreOffice and disabling Bluetooth are optional and asked up front,
so the rest of the run is unattended.

## Usage

```bash
bash setup.sh                                    # asks about LibreOffice + Bluetooth
bash setup.sh --yes                              # accept everything, no prompts
bash setup.sh --yes --keep-libreoffice --keep-bluetooth
bash setup.sh --help
```

Always pass explicit `--keep-*` / `--remove-*` flags when running over SSH.
Without a terminal the prompts silently default to **yes**, which will remove
things you meant to keep. See [AGENTS.md](AGENTS.md).

## chrome-window-limit.sh

Optional watcher for customers who click a launcher repeatedly and end up with
a screen full of browser windows. Keeps at most 5 Chrome windows open, closing
the oldest as new ones appear. Never closes the window currently in focus.

```bash
install -m 755 chrome-window-limit.sh ~/.local/bin/
MAX=3 ~/.local/bin/chrome-window-limit.sh --once    # test a single pass
```

To run it every login, drop a `.desktop` file in `~/.config/autostart/`
(see [AGENTS.md](AGENTS.md)). Logs to `~/.cache/chrome-window-limit.log`.

## Per-customer extras

Anything specific to one machine (games, browser shortcuts, accessibility
tweaks) is deliberately **not** in `setup.sh`. Recipes for those live in
[AGENTS.md](AGENTS.md).

## Requirements

apt-based distro, tested on Linux Mint 22.3 (Zena) / Ubuntu 24.04 (noble) base.
