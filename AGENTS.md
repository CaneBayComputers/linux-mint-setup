# AGENTS.md

Working notes for this repo. Recipes that worked, and gotchas that cost time.

Verified on Linux Mint 22.3 (Zena), Cinnamon 6.6.9, Ubuntu 24.04 (noble) base.

---

## Running desktop commands over SSH

`gsettings`, `dbus-send`, and `gnome-screenshot` all need the user's session
bus. Without these two exports they either fail or silently do nothing:

```bash
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus   # 1000 = the user's uid
export DISPLAY=:0
```

Check the uid with `ls /run/user/` and confirm someone is actually logged in
graphically with `who` (look for `tty7 (:0)`).

`gnome-screenshot -f /tmp/shot.png` is the fastest way to confirm a desktop
change actually rendered. `gnome-screenshot -d N` adds an N-second delay, which
is handy for capturing something after launching it.

**ImageMagick is not installed on stock Mint.** Pull screenshots down with
`scp` and do any cropping/measuring locally.

---

## Making the panel taller than the settings slider allows

The Panel settings slider stops at 60px. That is a UI limit only — the
underlying setting accepts more:

```bash
gsettings set org.cinnamon panels-height "['1:90']"
```

Format is `['<panelId>:<height>']`. Get the panel id from
`gsettings get org.cinnamon panels-enabled` (e.g. `['1:0:bottom']` → id 1).
Applies immediately, no restart.

> **Gotcha:** this value is outside the slider's range. If someone opens
> Panel settings and drags the height slider, it will likely clamp back to 60
> and the change is lost. Re-run the command if that happens.

## Making the panel *icons* bigger

Raising the panel height does **not** enlarge the icons. That is a separate
setting, and its default of `0` ("auto") does not track panel height:

```bash
gsettings get org.cinnamon panel-zone-icon-sizes
# '[{"panelId": 1, "left": 0, "center": 0, "right": 24}]'
```

Note the value is a **JSON string inside a gsettings string** — edit it as JSON,
don't hand-splice it:

```bash
python3 - <<'PY'
import json, subprocess
raw = subprocess.run(["gsettings","get","org.cinnamon","panel-zone-icon-sizes"],
                     capture_output=True, text=True).stdout.strip()
data = json.loads(raw[1:-1] if raw.startswith("'") else raw)
for z in data:
    if z.get("panelId") == 1:
        z["left"] = 64      # launcher zone
        z["center"] = 64
        z["right"] = 32     # systray / clock
subprocess.run(["gsettings","set","org.cinnamon","panel-zone-icon-sizes", json.dumps(data)])
PY
```

Measured result on a 1920x1080 screen: panel 60px→90px and icon zone 0→64
took the rendered launcher icons from **52px to 76px**.

---

## Adding a website launcher to the panel (e.g. Yahoo, Gmail)

Three parts: an icon, a `.desktop` file, and an entry in the applet's config.

**1. Icon** — save a high-res PNG to `~/.local/share/icons/`.

Sources that actually return usable sizes:

| Icon  | URL | Size |
|-------|-----|------|
| Yahoo | `https://s.yimg.com/cv/apiv2/social/images/yahoo_default_logo.png` | 500x500 |
| Gmail | `https://www.gstatic.com/images/branding/product/1x/gmail_2020q4_512dp.png` | 512x512 |

Dead ends: `https://www.google.com/s2/favicons?domain=X&sz=256` ignores `sz` and
caps out at 48px, too blurry for a large panel. `https://www.yahoo.com/favicon.ico`
returns HTTP 429. `s.yimg.com/rz/l/favicon.ico` works but is only 32x32.

**2. Desktop entry** in `~/.local/share/applications/yahoo.desktop`:

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=Yahoo
Comment=Open Yahoo in Google Chrome
Exec=/usr/bin/google-chrome-stable https://www.yahoo.com
Icon=/home/owner/.local/share/icons/yahoo.png
Terminal=false
Categories=Network;
StartupNotify=true
```

`Icon=` takes an absolute path. Use `--app=https://...` instead of a plain URL
if you want a standalone window with no tabs or address bar — but for most
customers the normal window is better, since they can still browse elsewhere.

**Add `--new-window`** so each launcher opens its own window instead of adding
a tab to whatever Chrome window is already open. Much easier to follow for a
customer who struggles with tab strips — each site then gets its own button in
the window list:

```ini
Exec=/usr/bin/google-chrome-stable --new-window https://www.yahoo.com
```

For the main Chrome entry, only change the `Exec=` under `[Desktop Entry]` —
leave the `[Desktop Action ...]` Exec lines alone, or the right-click
"New Window" / "New Incognito Window" items break. A naive
`sed 's/^Exec=.*/.../'` hits all three.

Then `update-desktop-database ~/.local/share/applications` and check it with
`desktop-file-validate` (silent output = valid).

**3. Add it to the panel launcher applet.** Find the instance id:

```bash
gsettings get org.cinnamon enabled-applets | tr ',' '\n' | grep panel-launchers
# 'panel1:left:1:panel-launchers@cinnamon.org:15'   <- trailing 15 is the id
```

Config lives at
`~/.config/cinnamon/spices/panel-launchers@cinnamon.org/15.json`. Append to
`launcherList.value`, which is a list of `.desktop` **filenames** resolved from
the standard app directories:

```bash
python3 - <<'PY'
import json
p = "/home/owner/.config/cinnamon/spices/panel-launchers@cinnamon.org/15.json"
cfg = json.load(open(p))
for e in ("yahoo.desktop", "gmail.desktop"):
    if e not in cfg["launcherList"]["value"]:
        cfg["launcherList"]["value"].append(e)
json.dump(cfg, open(p, "w"), indent=4)
PY
```

Append — don't replace — or you'll wipe the customer's existing launchers.
Leave `__md5__` alone; it tracks the schema, not the values.

> **Gotcha:** editing the JSON does nothing on its own. Cinnamon keeps applet
> settings in memory. Reload just that applet rather than restarting the whole
> desktop (`cinnamon --replace` flashes the screen for a user who is sitting there):
>
> ```bash
> dbus-send --session --dest=org.Cinnamon --type=method_call \
>   /org/Cinnamon org.Cinnamon.ReloadXlet \
>   string:'panel-launchers@cinnamon.org' string:'APPLET'
> ```

> **Second gotcha:** `ReloadXlet` picks up *list* changes but NOT a changed
> `Icon=` on an existing entry — Cinnamon caches resolved app icons separately.
> Symptom: `Gio.DesktopAppInfo` reports the new icon path but the panel still
> draws the old one. Only a full `cinnamon --replace` clears it:
>
> ```bash
> nohup cinnamon --replace >/dev/null 2>&1 & disown
> ```
>
> Check what Cinnamon *should* be resolving with:
> ```bash
> python3 -c "
> import gi; gi.require_version('Gio','2.0')
> from gi.repository import Gio
> print(Gio.DesktopAppInfo.new('google-chrome.desktop').get_icon().to_string())"
> ```

### Restyling an existing launcher (e.g. Chrome → Google Search look)

Don't edit `/usr/share/applications/*.desktop` — package updates overwrite it.
Copy it to the user directory, which takes precedence, and change only `Icon=`:

```bash
sed 's|^Icon=.*|Icon=/home/owner/.local/share/icons/google.png|' \
  /usr/share/applications/google-chrome.desktop \
  > ~/.local/share/applications/google-chrome.desktop
```

Google "G" logo, 512x512:
`https://www.gstatic.com/images/branding/product/1x/googleg_512dp.png`
(`.../product/1x/search_512dp.png` is a 404.)

This restyles Chrome everywhere — panel, menu, window list — which is usually
what you want for consistency.

---

## Mouse cursor and pointer speed (low-vision setups)

**The schema moved.** On Cinnamon 6.x the mouse lives in
`org.cinnamon.desktop.peripherals.mouse`. The older
`org.cinnamon.settings-daemon.peripherals.mouse` no longer exists and querying
it returns nothing at all — no error, just empty output, which reads like
"the setting isn't there" when really you're asking the wrong schema.

```bash
gsettings set org.cinnamon.desktop.interface cursor-size 96        # default 24
gsettings set org.cinnamon.desktop.peripherals.mouse speed -0.3    # range -1.0 .. 1.0, lower = slower
gsettings set org.cinnamon.desktop.peripherals.mouse locate-pointer true
```

Confirm a range before guessing at a value:
`gsettings range org.cinnamon.desktop.peripherals.mouse speed`.

Rendered cursor sizes measured on a 1920x1080 screen (visible arrow, not the
nominal box): size 24 → ~18x23px, size 64 → 48x61px, size 96 → ~70x90px.
A `cinnamon --replace` makes the new size apply everywhere reliably.

### Mouse trails are not available

There is no pointer-trail feature in Cinnamon or X11 — no gsettings key, no
`xset` option. Windows' "display pointer trails" has no equivalent. What you
*can* offer instead:

- `locate-pointer true` — press **Ctrl** and an animation pings the pointer location.
- Full-screen crosshairs that follow the pointer, via the magnifier at 1x zoom
  (so nothing is actually magnified):
  ```bash
  gsettings set org.cinnamon.desktop.a11y.magnifier mag-factor 1.0
  gsettings set org.cinnamon.desktop.a11y.magnifier show-cross-hairs true
  gsettings set org.cinnamon.desktop.a11y.applications screen-magnifier-enabled true
  ```
  Tune with `cross-hairs-thickness`, `cross-hairs-color`, `cross-hairs-opacity`.
- A high-visibility cursor theme — `GoogleDot-Black`, `HighContrast` and
  `XCursor-Pro-*` ship with Mint (`ls /usr/share/icons/`).

## Measuring a desktop change from a screenshot

Diffing a `gnome-screenshot -p` (with pointer) against a plain one isolates the
cursor so you can measure it:

```python
from PIL import Image, ImageChops
a=Image.open('with_p.png').convert('RGB'); b=Image.open('without_p.png').convert('RGB')
print(ImageChops.difference(a,b).getbbox())
```

> **Gotcha:** this is only valid if nothing else on screen changed. If the
> customer is sitting at the machine, an opened menu or a moved pointer lands in
> the same bounding box and you'll get a nonsense measurement (a "377x423px
> cursor"). Always eyeball the cropped region before trusting the number.
>
> More generally: on a machine someone is actively using, config files can
> change under you. Cinnamon writes the panel launcher JSON from its in-memory
> state, so a user dragging an icon off the panel silently overwrites your edit.
> Compare `ls --time-style=+%H:%M:%S` mtimes against when you last wrote.

## Chrome gotchas

- **`pkill -f google-chrome` does not match anything.** The real process path is
  `/opt/google/chrome/chrome`. Use `pgrep -f '/opt/google/chrome/chrome'`.
- **Don't kill Chrome to close it.** That sets `profile.exit_type` to `Crashed`
  and the customer gets a "Restore pages?" prompt next launch. Send `SIGTERM`
  to the *main* browser process — the one whose cmdline has no `--type=`:

  ```bash
  MAIN=$(pgrep -f '/opt/google/chrome/chrome' | while read -r p; do
           tr '\0' ' ' < /proc/$p/cmdline | grep -q -- '--type=' || echo "$p"; done | head -1)
  kill -TERM "$MAIN"
  ```
- If it did crash, fix `profile.exit_type` to `Normal` and `exited_cleanly` to
  `true` in `~/.config/google-chrome/Default/Preferences` — but **only while
  Chrome is closed**, otherwise it overwrites the file on exit.
- Cleanest way to close test windows is the window manager, not signals:
  ```bash
  wmctrl -lx | grep -i chrome | awk '{print $1}' | while read -r w; do wmctrl -i -c "$w"; done
  ```
  `wmctrl -c` sends `WM_DELETE_WINDOW`, so Chrome exits normally. Verify with
  `exit_type: Normal` afterwards.

> **Testing gotcha:** to prove `--new-window` works you must launch it while a
> Chrome window is *already open*. Chrome may have background processes but zero
> windows (`pgrep` says 14, `wmctrl -lx | grep -ci chrome` says 0) — launching
> from that state opens a window no matter what the flag says, and proves
> nothing. Count windows with `wmctrl`, not processes with `pgrep`.

---

## setup.sh gotchas

- **Prompts default to YES when there is no terminal.** `confirm()` falls back to
  yes if `/dev/tty` is unreadable, so a bare `--yes` run over SSH will remove
  LibreOffice and disable Bluetooth even if you wanted them kept. Always pass
  `--keep-libreoffice` / `--keep-bluetooth` explicitly for remote runs; flags
  beat `--yes` and skip the prompt entirely.
- **Codenames are detected, not hardcoded** (`VERSION_CODENAME` and
  `UBUNTU_CODENAME` from `/etc/os-release`), so the mirror block survives new
  Mint releases. Mint 22.3 = `zena` on `noble`.
- **The Mint mirror URL is bare** — `https://fastly.linuxmint.io`, no `/packages`
  suffix. Verify with `curl -o /dev/null -w '%{http_code}' <url>/dists/<codename>/Release`.
- **`-security` deliberately stays on `security.ubuntu.com`**, matching what
  Mint's own Software Sources tool does. Don't "fix" it to the base mirror.
- **Update Manager automation runs last** on purpose. Enabling it starts systemd
  timers, and they'd contend with the dpkg lock if the purges were still running.
  The two toggles in Preferences → Automation are:
  ```bash
  sudo mintupdate-automation upgrade enable      # "Apply updates automatically"
  sudo mintupdate-automation autoremove enable   # "Remove obsolete kernels and dependencies"
  ```
  Confirm via `/var/lib/linuxmint/mintupdate-automatic-{upgrades,removals}-enabled`.
- **`autoremove` misses `rhythmbox-data`** after purging `rhythmbox`, apparently
  because it isn't flagged auto-installed. It's listed explicitly in `PKGS` now.
  Other purged apps may leave similar `-data` orphans.
- `set -euo pipefail` does **not** abort on `some_cmd && VAR=1` when `some_cmd`
  fails — bash exempts AND-OR lists from errexit. That pattern is safe here.

## Verifying package removal

`dpkg -l | grep '^ii  rhythmbox'` prefix-matches `rhythmbox-data` and reports a
package as present when it isn't. Query exactly instead:

```bash
dpkg-query -W -f='${db:Status-Abbrev}' rhythmbox    # 'un' = gone, 'ii' = installed
```
