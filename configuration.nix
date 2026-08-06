# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, pkgs-unstable, noctalia, ... }:

let
  # NOTE: the nixos-unstable package set arrives as the `pkgs-unstable` module
  # argument above, imported once in flake.nix and handed over via specialArgs.
  # Don't re-import the `unstable` flake input here — flake inputs are not in
  # scope inside a module, only what specialArgs passes, so that fails with
  # "undefined variable 'unstable'".

  # DataGrip renders parts of its UI through Skia (skiko). The bundled
  # libskiko-linux-x64.so links against libGL.so.1 but its RUNPATH still points at
  # the upstream build directory, so the loader never finds libGL. skiko then
  # fails to load and every Skia-backed component throws UnsatisfiedLinkError —
  # the window paints but nothing responds to input. Putting libGL on
  # LD_LIBRARY_PATH is what makes the IDE usable.
  #
  # STILL REQUIRED on nixos-unstable's 2026.2.1 — do not delete this wrapper on
  # the assumption that a newer DataGrip fixed it. Verified against the unstable
  # store path: RUNPATH is
  #   /build/DataGrip-2026.2.1/plugins/remote-dev-server/selfcontained/lib
  # and libGL.so.1 is still in DT_NEEDED. Re-check with
  #   patchelf --print-rpath <drv>/datagrip/lib/skiko-awt-runtime-all/libskiko-linux-x64.so
  # before removing.
  #
  # --prefix, not --set: --set clobbers the variable, and the empty nix-ld
  # directory it previously pointed at contains no libGL at all.
  datagrip-wrapped = pkgs.symlinkJoin {
    name = "datagrip-wrapped";
    paths = [ pkgs-unstable.jetbrains.datagrip ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/datagrip \
        --unset WAYLAND_DISPLAY \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ pkgs.libGL ]}"
    '';
  };
in
{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Keep the vfat /boot partition from filling up with old generations.
  # boot.loader.systemd-boot.configurationLimit = 10;

  # Zen kernel (7.1.4 in this nixpkgs pin) instead of the 6.18 LTS default.
  # Zen carries desktop-latency patches — a different scheduler tune, higher
  # default HZ and preemption — which is the point on an interactive machine.
  #
  # Safe here specifically because nothing out-of-tree has to follow the kernel:
  # boot.extraModulePackages is empty, there is no NVIDIA driver, and the
  # filesystems are btrfs + vfat, both in-tree. (ZFS in particular pins you to
  # older kernels; this system does not use it.) Re-check this list before
  # adding a proprietary driver later.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # --- Hardware, firmware & Bluetooth ---
  # Ship redistributable firmware blobs (Wi-Fi/GPU) and, via the hardware scan's
  # mkDefault, enable AMD CPU microcode updates.
  hardware.enableRedistributableFirmware = true;

  # This machine has a Bluetooth adapter (hci0); enable the stack (GNOME provides the UI).
  # hardware.bluetooth.enable = true;
  # hardware.bluetooth.powerOnBoot = true;

  # Firmware updates over LVFS (BIOS/SSD/dock): `fwupdmgr refresh && fwupdmgr update`.
  services.fwupd.enable = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Kathmandu";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # ly is a small TTY greeter. GDM was the last GNOME dependency here: its
  # greeter IS GNOME Shell, so it kept gnome-shell (2.1 GiB) and mutter
  # (1.3 GiB) in the system closure purely to draw a login box.
  #
  # ly's NixOS module sets security.pam.services.ly.enableGnomeKeyring from
  # services.gnome.gnome-keyring.enable, so the login-password keyring unlock
  # follows automatically — no extra PAM wiring needed.
  # greetd + tuigreet. Like ly this is a TTY greeter, so it keeps gnome-shell
  # and mutter out of the closure the way GDM could not.
  #
  # The module sets security.pam.services.greetd.enableGnomeKeyring from
  # services.gnome.gnome-keyring.enable, so the login-password keyring unlock
  # follows automatically — no extra PAM wiring needed.
  services.greetd = {
    enable = true;
    # Adjusts the systemd unit (TTYPath, TTYVTDisallocate, StandardError to
    # journal) so boot messages don't spam over the TUI.
    useTextGreeter = true;
    settings.default_session = {
      # Green-on-black terminal styling. tuigreet has no animation (that was
      # an ly feature) but it does take a colour theme and layout options.
      # Invalid theme keys are ignored rather than fatal, so a typo here
      # cannot leave the machine without a greeter.
      command = builtins.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time --time-format '%H:%M:%S  %a %d %b'"
        "--remember --remember-session"
        "--asterisks"
        "--greeting 'ACCESS REQUIRED'"
        "--width 44 --container-padding 2"
        ("--theme '" + builtins.concatStringsSep ";" [
          "container=black"
          "border=green"
          "title=green"
          "greet=lightgreen"
          "prompt=lightgreen"
          "input=lightgreen"
          "text=green"
          "time=lightgreen"
          "action=green"
          "button=lightgreen"
        ] + "'")
        "--cmd niri-session"
      ];
      user = "greeter";
    };
  };

  programs.niri.enable = true;

  # These two came free with the GNOME desktop module. They are still needed
  # without it: gnome-keyring backs libsecret (browser/git credentials), and
  # dconf is where GTK apps keep their settings.
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;

  # Backing daemons for nemo (see home.packages). Neither is pulled in by the
  # package itself, and without them nemo starts but silently loses features:
  #   gvfs    — Trash (delete becomes "unsupported"), removable-drive mounting,
  #             and the smb:// / sftp:// / mtp:// location bar schemes.
  #   tumbler — thumbnails; without it image/video/PDF files render as generic
  #             icons in icon view.
  # udisks2 is the third leg and is already on (NixOS enables it by default).
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Text-to-speech is on by default via a module, and nothing here wants it.
  # It drags in espeak-ng -> mbrola -> mbrola-voices, a 645 MiB voice database
  # (larger than VS Code). Re-enable if a screen reader is ever needed.
  services.speechd.enable = false;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users."nitesh" = {
    isNormalUser = true;
    description = "Nitesh";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    shell = pkgs.zsh;

    packages = with pkgs; [
      #  thunderbird
    ];
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
  };

  # Install firefox.
  programs.firefox.enable = true;
  programs.zsh.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "nitesh"
    ]; # <-- Add your username here
    # Deduplicate the store by hard-linking identical files.
    auto-optimise-store = true;
  };

  # Reclaim disk automatically: collect garbage weekly, keeping 30 days of history.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  # nix-ld supplies an FHS-style loader for downloaded binaries that were not
  # built for NixOS (language servers, JetBrains remote backends, toolchains
  # fetched by npm/pip/gradle). The loader alone is not enough — without
  # libraries listed here there is nothing for those binaries to link against,
  # which is the failure the datagrip-wrapped comment above describes.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
    curl
    glib
    libGL
    libxkbcommon
    fontconfig
    freetype
    libx11
    libxext
    libxrender
    libxtst
    libxi
  ];
  services.xserver.excludePackages = with pkgs; [
    xterm
    xmessage
  ];
  environment.systemPackages = with pkgs; [
    #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #  wget
    nvd
    brave
    neovim
    git
    foot
    ghostty
    fastfetch
    postman
    obsidian
    tmux
    jdk17
    curl
    wget
    zip
    unzip
    ripgrep
    fd
    jq
    xdg-utils
    xdg-user-dirs
    libsecret
    xwayland
    wl-clipboard
    wl-clip-persist
    cliphist
    xwayland-satellite
    # NOTE: stable, and unwrapped. There used to be an idea-wrapped that ran it
    # through XWayland (--unset WAYLAND_DISPLAY), because JetBrains Runtime's
    # native Wayland backend creates a real xdg_toplevel per tooltip — hovering
    # the git gutter produced 214 open/close pairs in a minute, which re-tiled
    # the IDE and made the noctalia taskbar flicker in step. That wrapper was
    # dead code: this line always installed the plain package. Kept as a note in
    # case the flicker ever comes back.
pkgs-unstable.jetbrains.idea
    datagrip-wrapped
    gcc
    adwaita-icon-theme
    gnome-themes-extra
    # gparted-full
    vscode
    mesa-demos
    podman-desktop
  ];

  # A Nerd Font is required for the icons/glyphs used by eza --icons, powerlevel10k
  # and fzf in the shell config; plus general text and emoji coverage.
  #
  # `nerd-fonts.symbols-only` provides the "Symbols Nerd Font" family, which
  # contains ONLY the Nerd-Font glyph range. fontconfig uses it as a system-wide
  # fallback for those codepoints, so apps that don't use a Nerd Font as their main
  # font (noctalia, Brave, GTK apps, …) still render Nerd icons instead of tofu.
  # (JetBrainsMono Nerd Font alone only fixes apps that explicitly select it, e.g.
  # the terminal.)
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
    noto-fonts
    noto-fonts-color-emoji
    inter        # UI / sans-serif — see defaultFonts below
    source-serif # long-form reading serif
  ];

  # Without this, fontconfig picks its own fallback for the generic families and
  # everything lands on DejaVu — including all of Brave, which stores no font
  # preferences of its own. noto-fonts was installed but nothing ever selected it.
  #
  # Only apps that ask for a *generic* family go through here. Apps that pin a
  # font by name opt out: ghostty (config/ghostty/config), noctalia
  # (~/.local/state/noctalia/settings.toml) and the foot spawns in niri's
  # config.kdl. Those are set separately.
  #
  # Family names verified against the packages with fc-scan: the Inter package
  # also ships "Inter Display"/"Inter Variable", and source-serif ships several
  # optical sizes — "Inter" and "Source Serif 4" are the text-weight families.
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Inter" "Noto Sans" ];
    serif     = [ "Source Serif 4" "Noto Serif" ];
    monospace = [ "JetBrainsMono Nerd Font" ];
    emoji     = [ "Noto Color Emoji" ];
  };

  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
  ];
  services.flatpak.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true; # Optional: provides a `docker` command
  };
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).

  # --- POLKIT & AUTHENTICATION AGENT CONFIGURATION ---
  security.polkit.enable = true;

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "niri.service" ];
    wants = [ "niri.service" ];
    after = [ "niri.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # ----------------------------------------------------
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
    systemd.enable = true;
  };

  # --- System maintenance & reliability ---
  # Periodic TRIM for the NVMe SSD.
  services.fstrim.enable = true;

  # Scrub the btrfs volumes to detect (and, with redundancy, repair) bit rot.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  # Compressed RAM swap: fast, low-latency relief under memory pressure.
  # The kernel gives this the higher priority, so it is used first.
  zramSwap.enable = true;

  # Disk-backed swap for real overflow capacity once zram is exhausted. On
  # btrfs the swapfile must be NoCoW and uncompressed; the NixOS swap module
  # handles that for us via `btrfs filesystem mkswapfile`.
  # Note: at 10 GiB this is smaller than RAM (14 GiB), so it is not sized for
  # hibernation — which is not configured on this host anyway.
  swapDevices = [
    {
      device = "/swapfile";
      size = 10 * 1024; # MiB
    }
  ];

  boot.kernel.sysctl = {
    # The default of 60 assumes swapping means a disk seek. Here the first
    # swap tier is zram, so reclaiming anonymous pages is far cheaper than
    # throwing away page cache. 100 leans into that without the zram-only
    # advice of 180, which would fill zram and spill to the NVMe sooner.
    "vm.swappiness" = 100;
    # Swap readahead is a disk optimisation: it reads neighbouring pages on
    # the assumption a seek is expensive. zram is already in RAM, so this
    # only burns CPU decompressing pages nobody asked for.
    "vm.page-cluster" = 0;
  };
  # ----------------------------------------

  system.stateVersion = "26.05"; # Did you read the comment?

}
