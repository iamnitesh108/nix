{ config, pkgs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "nitesh";
  home.homeDirectory = "/home/nitesh";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "26.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')

    mpv
    micro
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # xdg.configFile."foot/foot.ini".text = ''
  #   [main]
  #   font=JetBrainsMono Nerd Font:size=11
  # '';

  xdg.configFile."ghostty/config".source = ./config/ghostty/config;

  xdg.configFile."foot".source =
  config.lib.file.mkOutOfStoreSymlink "/etc/nixos/dotfiles/foot";

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/nitesh/etc/profile.d/hm-session-vars.sh
  #
  # XCURSOR_THEME / XCURSOR_SIZE are set by home.pointerCursor below (single
  # source of truth), so no separate home.sessionVariables block is needed.

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    size = 24;
  };

  # NOTE: shell integration for the tools below is intentionally OFF.
  # ~/.zshrc is hand-managed (not by home-manager) and already initializes
  # atuin/zoxide/fzf and defines eza aliases itself, with custom flags
  # (e.g. `zoxide init --cmd cd`, `atuin init --disable-up-arrow`). Enabling
  # home-manager's integration here would either be a no-op (it only injects
  # into a home-manager-managed zsh) or double-bind these tools.

  # Atuin configuration
  programs.atuin = {
    enable = true;
    enableZshIntegration = false;

    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      search_mode = "fuzzy";
      filter_mode = "global";
      style = "compact";
    };
  };
  programs.zoxide = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.bat = {
    enable = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = false;
  };
  # Let Home Manager install and manage itself.
  # programs.home-manager.enable = true;
}
