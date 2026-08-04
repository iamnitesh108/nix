# NixOS Configuration — Context & Map

> Orientation doc for humans and LLMs. If you were handed only `/etc/nixos`, the
> single most important thing to know is in **§2**: a lot of this machine's real
> behaviour lives in **hand-managed dotfiles under `~` that are NOT in this repo**.
> Read §2 before reasoning about shell, editor, terminal, or clipboard behaviour.
>
> Last updated: 2026-08-02.

---

## 1. System at a glance

| | |
|---|---|
| Distro | NixOS **26.05** (flake-based) |
| Host | `nixos` — **laptop** (chassis type 10), **AMD** CPU (`kvm-amd`) |
| Config style | Flake + **home-manager** (as a NixOS module) |
| Desktop | **niri** (Wayland scrolling WM) + **noctalia** shell/bar, with **GNOME/GDM** also available |
| Wayland socket | `wayland-1` (⚠ the number can change between logins — see §6) |
| Filesystems | **btrfs** subvolumes (`/`, `/home`, `/nix`) on one device; vfat `/boot` |
| Primary user | `nitesh` (shell: **zsh**) |
| Rebuild | `sudo nixos-rebuild switch --flake /etc/nixos#nixos` |

---

## 2. Where configuration lives — the Nix / dotfile split (READ FIRST)

This machine is configured in **two disjoint places**. Confusing them is the main
source of "why isn't my change taking effect".

### A. Nix-managed — declarative, in THIS repo (`/etc/nixos`)
Applied atomically by `nixos-rebuild switch`. Covers the **system** (services,
hardware, packages, fonts) and a **small slice of the user env** via home-manager
(`home.nix`: a few CLI tools + cursor).

### B. Hand-managed dotfiles — imperative, under `~`, NOT in this repo
The interactive environment (shell, editor, terminals, multiplexer, prompt) is
configured with **plain dotfiles the user edits directly**. home-manager does
**not** manage these. They are invisible to anyone reading only `/etc/nixos`.

| Concern | File (hand-managed) | Framework / notes |
|---|---|---|
| Shell | `~/.zshrc` | **zinit** plugin manager, powerlevel10k, fzf-tab, custom nix-store-aware caching; self-inits fzf/atuin/zoxide with custom flags (`zoxide init --cmd cd`, `atuin --disable-up-arrow`) |
| Prompt | `~/.p10k.zsh` | powerlevel10k, `POWERLEVEL9K_MODE=nerdfont-v3` |
| Multiplexer | `~/.tmux.conf` | `set-clipboard on`, `terminal-features ',*:clipboard'`, `update-environment WAYLAND_DISPLAY` |
| Editor | `~/.config/nvim/` | **LazyVim** (starter layout: `init.lua` + `lua/config/*`, `lua/plugins/*`) |
| Terminal (foot) | `~/.config/foot/foot.ini` | created this session (§5) |
| Terminal (ghostty) | `~/.config/ghostty/config` | created this session (§5) |
| Compositor | `~/.config/niri/config.kdl` | niri WM (`niri validate -c <file>` checks it; hot-reloads on save). Also `noctalia.kdl`, `scripts/` |

### Why the split? (deliberate — "Option B")
The user's `~/.zshrc` is a large, finely-tuned zinit/p10k setup. Porting it into
home-manager's `programs.zsh` was considered and **rejected** because that module
would:
- take ownership of `~/.zshrc` (making it a **read-only `/nix/store` symlink**),
  which breaks the in-file `toggle-theme` function that does `sed -i ~/.zshrc`;
- run its **own `compinit`**, conflicting with zinit's `zicompinit`;
- risk a stale `~/.zshrc.zwc` (nix-store files have epoch mtime) shadowing future
  home-manager updates.

**Consequence to remember:** because zsh is hand-managed, the
`enableZshIntegration` flags in `home.nix` are **intentionally `false`** (see §5).
home-manager only injects shell integration into a zsh **it** manages; here the
`~/.zshrc` performs that integration itself. Turning those flags on would either
be a no-op or **double-bind** the tools.

---

## 3. Files in `/etc/nixos`

| File | Role |
|---|---|
| `flake.nix` | Inputs (`nixpkgs` = `nixos-26.05`, `home-manager` = `release-26.05`, `noctalia`) and the `nixosConfigurations.nixos` output. Wires home-manager in with `useGlobalPkgs`/`useUserPackages` and `home-manager.users.nitesh = ./home.nix`. Adds the noctalia cachix substituter. |
| `configuration.nix` | System config: boot, networking, desktop (niri + GNOME/GDM), pipewire, PostgreSQL 18, a large `nix-ld` library set (for JetBrains/DataGrip), `environment.systemPackages`, fonts, maintenance/firmware settings. |
| `home.nix` | home-manager user config for `nitesh`: `mpv`, atuin (settings only), zoxide/fzf/eza/bat (packages only — integration off), and `home.pointerCursor` (the single source of the Adwaita cursor + `XCURSOR_*`). |
| `hardware-configuration.nix` | Generated. btrfs mounts, `kvm-amd`, and `hardware.cpu.amd.updateMicrocode` gated on `hardware.enableRedistributableFirmware`. **Do not hand-edit.** |
| `flake.lock` | Pins the three inputs. |
| `context.md` | This file. |

> **Flake gotcha:** `/etc/nixos` is a git repo, and flakes only see **git-tracked**
> files. A newly created `*.nix` (or any file referenced via `./…`) must be
> `git add`-ed or evaluation fails with a missing-path error.

---

## 4. Notable design points / gotchas

- **Two desktops coexist:** niri (via noctalia) and GNOME. `services.xserver.enable`
  is on for GDM/xkb; sessions are Wayland.
- **Cursor:** `home.pointerCursor` (in `home.nix`) is the **single source of truth**
  for the Adwaita cursor and auto-exports `XCURSOR_THEME`/`XCURSOR_SIZE`. Earlier
  duplicate definitions in `environment.variables` and `home.sessionVariables` were
  removed (§5).
- **nix-ld:** the long `programs.nix-ld.libraries` list exists so dynamically-linked
  binaries (JetBrains IDEs, `datagrip-wrapped`) run outside Nix. Candidate for
  extraction into its own module later.
- **Fonts / Nerd icons (two layers):** (1) a full Nerd Font
  (`nerd-fonts.jetbrains-mono`) that an app must **explicitly select** — this is what
  the terminal uses (foot/ghostty configs). (2) **`nerd-fonts.symbols-only`**
  ("Symbols Nerd Font"), a glyph-only font fontconfig uses as a **system-wide
  fallback** for the Nerd codepoint range, so apps that do NOT select a Nerd Font
  (noctalia bar, Brave, GTK) still render icons. Without (2) those apps fall back to
  DejaVu Sans (no Nerd glyphs) → **tofu/gibberish**. After any font change you must
  rebuild **and restart the apps** — fontconfig's cache refreshes on activation, but
  already-running apps don't re-scan.
- **Clipboard:** see §6 for the full Wayland + tmux + nvim chain.
- **Shell startup / plugin load order (`~/.zshrc`):** the shell uses **powerlevel10k
  instant prompt** + **zinit turbo (`zinit wait`)**. This creates a window where the
  prompt is already interactive but deferred plugins have **not** loaded yet. Rule of
  thumb: anything that only affects *display* or *later* keystrokes (syntax
  highlighting, autosuggestions, completions) is safe to defer via `zinit wait`;
  anything that **changes command behaviour and might be the first command typed**
  must be loaded **synchronously**. Concretely, **zoxide owns `cd` (`--cmd cd`)**, so
  it is sourced synchronously — deferring it made the first `cd` in a fresh shell run
  builtin `cd` and fail (see §5, "zsh: zoxide `cd` load"). fzf and atuin are likewise
  sourced synchronously; fast-syntax-highlighting / autosuggestions / completions stay
  deferred on purpose.
- **Startup ownership — don't start the same thing twice.** Session programs can be
  launched from *either* the niri config (`spawn-at-startup`) *or* a NixOS systemd
  user unit (`programs.*` / `systemd.user.services.*`). Doing both races them: niri
  spawned **noctalia**, then its systemd unit (wantedBy `graphical-session.target`)
  also tried, hit "noctalia is already running", and failed into `start-limit-hit`
  (looked "dead" but was really a conflict). Rule: **one owner per program** — prefer
  the systemd unit when it exists (`Restart=on-failure`, journald, ordering) and
  comment the niri `spawn-at-startup`. Before assuming a "dead" unit is broken, check
  `systemctl --user status <unit>` + `pgrep -af <proc>` — it may just be losing the race.

---

## 5. Change log — 2026-08-02

### `configuration.nix` — reliability & maintenance (added)
- `nix.gc` (weekly, keep 30 days) + `nix.settings.auto-optimise-store` — stop
  `/nix` filling up; dedupe the store.
- `boot.loader.systemd-boot.configurationLimit = 10` — cap generations so vfat
  `/boot` can't fill.
- `services.fstrim.enable` — TRIM the NVMe SSD.
- `services.btrfs.autoScrub` (weekly) — detect bit rot on the btrfs volumes.
- `zramSwap.enable` — there was **no swap**; avoids hard OOM kills.

### `configuration.nix` — hardware/firmware (Group A, added)
- `hardware.enableRedistributableFirmware = true` — Wi-Fi/GPU firmware; also flips
  `hardware.cpu.amd.updateMicrocode` on (it was gated on this and thus off).
- `hardware.bluetooth.enable` + `powerOnBoot` — adapter `hci0` was present but the
  stack wasn't enabled.
- `services.fwupd.enable` — firmware updates via LVFS (`fwupdmgr refresh && update`).
- `fonts.packages = [ nerd-fonts.jetbrains-mono nerd-fonts.symbols-only noto-fonts
  noto-fonts-color-emoji ]` — **no Nerd Font was installed**, so shell icons rendered
  as tofu. `nerd-fonts.symbols-only` ("Symbols Nerd Font") was added so **system-wide**
  apps that don't select a Nerd Font (noctalia, Brave, GTK) get Nerd icons via
  fontconfig fallback — without it they fell back to DejaVu Sans → gibberish (see §4).
  (26.05 uses the `nerd-fonts.*` namespace, not `nerdfonts.override`; and
  `noto-fonts-emoji` → `noto-fonts-color-emoji`.)

### `configuration.nix` / `home.nix` — cursor dedup (removed)
- Removed `environment.variables.XCURSOR_*` (system) and
  `home.sessionVariables.XCURSOR_*` (home). Both duplicated `home.pointerCursor`,
  which is now the sole source.

### `home.nix` — zsh integration flags (changed → false)
- `programs.{atuin,zoxide,fzf,eza}.enableZshIntegration` set to **`false`**.
  Rationale in §2: zsh is hand-managed, so these were inert no-ops that would
  double-init the tools if the shell were ever put under home-manager. The
  `~/.zshrc` integrates these itself with custom flags.

### Terminal font configs (created — hand-managed dotfiles)
- `~/.config/foot/foot.ini` → `font=JetBrainsMono Nerd Font:size=11`
- `~/.config/ghostty/config` → `font-family = JetBrainsMono Nerd Font`
- Needed because installing the font doesn't change what a terminal *selects*.
  `~/.p10k.zsh` was already `nerdfont-v3`, so it was left untouched.

### Clipboard fix (changed — see §6)
- `~/.zshrc` — replaced the `WAYLAND_DISPLAY` `wayland-0` hardcode with live-socket
  detection.
- `~/.config/nvim/lua/config/options.lua` — explicit `vim.opt.clipboard = "unnamedplus"`.

### zsh: zoxide `cd` load (changed)
- `~/.zshrc` — zoxide (which owns the `cd` command via `--cmd cd`) was loaded via
  `zinit wait` (turbo/deferred), which only fires on the first `precmd` — i.e.
  **after** the first command runs. So the *first* `cd` in every fresh shell
  (typical in a newly-opened tmux pane) fell through to **builtin `cd`** and failed
  with `cd: no such file or directory`. It's now sourced **synchronously** (like
  fzf/atuin), so `cd` is defined before the first command. Symptom of the
  p10k-instant-prompt + zinit-turbo window: the prompt is interactive before
  deferred plugins have loaded.

### `~/.zshrc` — cleanup of dead/wrong references (changed)
Correctness fixes for leftovers from a non-NixOS origin (startup was already ~60ms —
this was **not** a performance change; the config's instant-prompt + turbo + init
caching are already well tuned):
- `BROWSER=Browser` → `brave` (was an invalid command name).
- Removed the dead `/usr/lib/ccache/bin` PATH prepend (that path only exists on
  Debian/Arch; NixOS uses `programs.ccache`).
- `dotfiles` alias: `/usr/bin/git` → `git` (real git is `/run/current-system/sw/bin/git`).
- `preview` alias → **function** using `xdg-open` (old `open` is macOS-only, and an
  alias can't take `$@`).
- Removed the duplicate unconditional `~/.p10k.zsh` source at end of file (already
  sourced in the THEME LOADING block under `USE_P10K`; the re-source was wrong under
  starship).
- Left as-is on purpose (preferences / harmless, flagged not changed): `PAGER=cat`,
  `alias cat='bat …'`, the global `fzf` preview alias (footgun for non-file `fzf`),
  and the inert SDKMAN guard (`~/.sdkman` absent).

### niri (`~/.config/niri/config.kdl`) — review + noctalia startup fix (changed)
- **noctalia double-start fixed.** It was launched by BOTH the niri
  `spawn-at-startup "noctalia"` AND its NixOS systemd unit
  (`programs.noctalia.systemd.enable`). They raced: niri won, the systemd unit failed
  repeatedly with "noctalia is already running" → `start-limit-hit` (so it *looked*
  dead). Resolved by keeping **systemd as the sole owner** (correct v5 native-C++
  `ExecStart`, `Restart=on-failure`) and **commenting the niri spawn**. No
  `configuration.nix` change / rebuild. See the §4 "Startup ownership" gotcha.
- **Commented (verified redundant, not removed):** the niri `spawn-at-startup` for
  `polkit-gnome-authentication-agent-1` (already run by an active systemd user unit),
  and the `QT_QPA_PLATFORMTHEME "qt6ct"` / `QT_STYLE_OVERRIDE "kvantum"` env vars
  (neither engine is installed → dead).
- **Tidy-ups:** single-monitor output `position x=1280` → `x=0`; corrected two stale
  default comments (a "waybar" note above the `xwayland-satellite` spawn; a "rounded
  corners" label on a `geometry-corner-radius 0` rule).
- `niri validate -c ~/.config/niri/config.kdl` passes after all edits.

---

## 6. Clipboard sync — full picture

### The chain (Wayland)
`GUI app` ⇄ **Wayland clipboard** ⇄ `wl-copy`/`wl-paste` ⇄ apps.
- **Neovim** copy/paste uses its clipboard *provider*, which shells out to
  `wl-copy`/`wl-paste`. Those need `WAYLAND_DISPLAY` pointing at the **live**
  compositor socket.
- **tmux** has `set-clipboard on` + `terminal-features ',*:clipboard'` (OSC 52) and
  `update-environment WAYLAND_DISPLAY`.
- **Clipboard managers** run and are healthy: `cliphist` (text+image `wl-paste
  --watch`) and a noctalia clip watcher — so history/persistence is fine.

### Root cause of "`p` doesn't paste; `Ctrl+Shift+V` does; clipboard out of sync in tmux"
`~/.zshrc` forced `WAYLAND_DISPLAY` to **`wayland-0`** as a fallback, but this
machine's socket is **`wayland-1`**. Inside tmux (where a persistent server can
hand panes a stale/empty `WAYLAND_DISPLAY`), the fallback pointed `wl-copy`/
`wl-paste` at a **non-existent socket**, so they silently failed:
- Neovim `p` (which reads the `+` register via `wl-paste`) got nothing → no paste.
- `Ctrl+Shift+V` still worked because that's the **terminal** pasting the real
  Wayland clipboard directly, bypassing Neovim's provider.
- Copies/pastes made **inside tmux** never reached the real clipboard → apps felt
  out of sync.

Note: **Neovim's option was not the problem** — this is LazyVim, which sets
`clipboard = unnamedplus` by default.

### What changed and why
1. **`~/.zshrc`** — the old line
   `[[ -n "$TMUX" ]] && export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"`
   was replaced with a block that, inside tmux, checks whether `WAYLAND_DISPLAY` is
   empty **or points at a dead socket**, and if so probes `$XDG_RUNTIME_DIR` for a
   live `wayland-*` socket (`-S` test) and exports it. This **self-heals** across
   logins where the socket number changes — no hardcoded number.
2. **`~/.config/nvim/lua/config/options.lua`** — added explicit
   `vim.opt.clipboard = "unnamedplus"` so `y`/`p` route through the system
   clipboard regardless of any upstream LazyVim default change. (Belt-and-suspenders;
   not the root cause.)

### Activating / testing after a change here
- The zsh fix runs at shell startup. In an existing tmux pane: `exec zsh` (or reset
  the persistent server once with `tmux kill-server`).
- **Launch Neovim from a corrected shell** — nvim captures `WAYLAND_DISPLAY` at
  launch; an already-running nvim won't pick up the fix until restarted.
- Test: `wl-copy "hi"` then in nvim normal mode `p` → pastes `hi`; and `yy` in nvim
  should be pasteable in other apps.

---

## 7. Applying changes & validating (no-rebuild checks)

- **Full rebuild:** `sudo nixos-rebuild switch --flake /etc/nixos#nixos`
- **Evaluate without building/activating** (catches option/type/syntax errors):
  `nix eval --raw /etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel.drvPath`
- **Check a single resolved option:**
  `nix eval --json /etc/nixos#nixosConfigurations.nixos.config.<option.path>`
- **Dotfiles are not part of the rebuild** — editing `~/.zshrc`, `~/.config/nvim`,
  etc. takes effect on the next shell/editor start, independent of Nix.

---

## 8. Open / optional follow-ups (not yet applied)
- `programs.direnv` + `nix-direnv` (home-manager) for per-project dev envs.
- Managed git identity via `programs.git` (currently `~/.gitconfig`, hand-managed).
- `boot.tmp.useTmpfs = true` for faster builds/temp.
- A `formatter` flake output (nixfmt-rfc-style) + normalizing tabs vs spaces.
- Split the large `nix-ld` library list into its own module.
