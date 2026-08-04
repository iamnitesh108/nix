# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  noctalia,
  ...
}:

let
  # DataGrip 2026.2 renders parts of its UI through Skia (skiko). The bundled
  # libskiko-linux-x64.so links against libGL.so.1 but its RUNPATH still points at
  # the upstream build directory (/build/DataGrip-*/plugins/remote-dev-server/...),
  # so the loader never finds libGL. skiko then fails to load and every Skia-backed
  # component throws UnsatisfiedLinkError — the window paints but nothing responds
  # to input. Putting libGL on LD_LIBRARY_PATH is what makes the IDE usable.
  #
  # --prefix, not --set: --set clobbers the variable, and the empty nix-ld
  # directory it previously pointed at contains no libGL at all.
  datagrip-wrapped = pkgs.symlinkJoin {
    name = "datagrip-wrapped";
    paths = [ pkgs.jetbrains.datagrip ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/datagrip \
        --unset WAYLAND_DISPLAY \
        --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.libGL ]}"
    '';
  };

  # Run IDEA through XWayland rather than JetBrains Runtime's native Wayland backend.
  # That backend creates a real xdg_toplevel for every tooltip — hovering the git gutter
  # produced 214 open/close pairs in a minute, which re-tiles the IDE and makes the
  # noctalia taskbar (which enumerates toplevels) flicker in step. X11 tooltips are
  # override-redirect, so neither the tiler nor the taskbar ever sees them.
  # DISPLAY=:0 is already in the session env courtesy of xwayland-satellite.
  idea-wrapped = pkgs.symlinkJoin {
    name = "idea-wrapped";
    paths = [ pkgs.jetbrains.idea ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/idea \
        --unset WAYLAND_DISPLAY
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
  boot.loader.systemd-boot.configurationLimit = 10;

  # --- Hardware, firmware & Bluetooth ---
  # Ship redistributable firmware blobs (Wi-Fi/GPU) and, via the hardware scan's
  # mkDefault, enable AMD CPU microcode updates.
  hardware.enableRedistributableFirmware = true;

  # This machine has a Bluetooth adapter (hci0); enable the stack (GNOME provides the UI).
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

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

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  programs.niri.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

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
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    
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
    idea-wrapped
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
  ];

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
  # ----------------------------------------

  system.stateVersion = "26.05"; # Did you read the comment?

}
