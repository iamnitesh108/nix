{ config, pkgs, ... }:

let
  # ── nemo-only icon theme ────────────────────────────────────────────────
  # Papirus is deliberately NOT set as the system icon theme. Scoping it to one
  # app is awkward because nemo resolves file icons through
  # gtk_icon_theme_get_default(), which reads GtkSettings — so neither the
  # `-gtk-icon-theme` CSS property nor any env var can reach it (GTK3 has
  # GTK_THEME but no GTK_ICON_THEME).
  #
  # What does work: GTK3 merges gtk-3.0/settings.ini out of XDG_CONFIG_DIRS,
  # ranked *below* ~/.config/gtk-3.0/settings.ini. Verified against
  # Gtk.Settings directly — with the user file's gtk-icon-theme-name removed, a
  # settings.ini reached via XDG_CONFIG_DIRS sets the theme; with it present,
  # the user file wins. So this only works while gtk.iconTheme stays unset
  # below. If you ever set gtk.iconTheme, this silently stops taking effect.
  #
  # Corollary: the same trick cannot set nemo's font, because the user file
  # *does* set gtk-font-name (Inter 11) and would outrank it. The monospace
  # face is applied via CSS instead — see gtk.gtk3.extraCss.
  nemoGtkSettings = pkgs.writeTextDir "gtk-3.0/settings.ini" ''
    [Settings]
    gtk-icon-theme-name=Papirus-Dark
  '';

  # XDG_DATA_DIRS is prefixed rather than installing papirus-icon-theme into
  # the profile, so the theme is visible only to this process — no other app
  # can even enumerate it.
  nemo-tui = pkgs.symlinkJoin {
    # nemo-with-extensions is itself a symlinkJoin and carries no `version`.
    name = "nemo-tui-${pkgs.nemo.version}";
    paths = [ pkgs.nemo-with-extensions ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      # makeWrapper rather than wrapProgram: wrapProgram would `mv` the joined
      # symlink onto $out/bin/.nemo-wrapped, which already exists here (nixpkgs
      # wraps nemo twice, leaving both .nemo-wrapped and .nemo-wrapped_).
      rm $out/bin/nemo
      makeWrapper ${pkgs.nemo-with-extensions}/bin/nemo $out/bin/nemo \
        --prefix XDG_DATA_DIRS   : "${pkgs.papirus-icon-theme}/share" \
        --prefix XDG_CONFIG_DIRS : "${nemoGtkSettings}"

      # Re-point D-Bus activation at the wrapper. Without this, a window opened
      # via xdg-open or another app's "show in file manager" starts the
      # unwrapped binary and comes up with the system icon theme instead.
      for f in share/dbus-1/services/nemo.FileManager1.service \
               share/dbus-1/services/nemo.service; do
        rm "$out/$f"
        substitute "${pkgs.nemo-with-extensions}/$f" "$out/$f" \
          --replace-fail "${pkgs.nemo-with-extensions}/bin/nemo" "$out/bin/nemo"
      done
    '';
  };
in
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

    # Cinnamon's file manager, re-wrapped above to carry its own icon theme.
    # The underlying nemo-with-extensions is used rather than bare `nemo`: plain
    # nemo cannot load extensions installed as separate packages (it looks in
    # its own store path for them), so the wrapper is the only way to get
    # archive extract/compress, emblems and folder colours. It bundles
    # nemo-fileroller, nemo-python, nemo-emblems and folder-color-switcher —
    # the same set a stock Mint install ships.
    # Requires services.gvfs + services.tumbler, enabled in configuration.nix.
    nemo-tui
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # Gradle daemons are the largest memory consumer on this machine after the
    # IDE, and they outlive the builds that spawned them — several idle daemons
    # holding ~2 GiB between them is normal without this. Cap the heap and let
    # idle daemons exit after 30 minutes.
    #
    # WARNING: home-manager renders this into /nix/store, which is world
    # readable. ~/.gradle/gradle.properties is also the conventional place for
    # artifactUsername/artifactPassword — never put credentials in this block.
    # Keep those in a hand-managed file or the environment.
    ".gradle/gradle.properties".text = ''
      org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m
      org.gradle.daemon.idletimeout=1800000
      org.gradle.console=verbose
    '';
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

  # GTK reads `gtk-font-name` for window chrome (menus, tabs, titlebars) rather
  # than fontconfig's sans-serif, so setting fonts.fontconfig.defaultFonts in
  # configuration.nix is not enough on its own — this is the other half.
  # Notably it is what moves Brave's tab/menu chrome off DejaVu.
  # Writes ~/.config/gtk-3.0/settings.ini, which did not previously exist.
  gtk = {
    enable = true;
    font = {
      name = "Inter";
      size = 11;
      package = pkgs.inter;
    };

    # Dark theme for GTK apps, nemo in particular.
    #
    # niri already exports GTK_THEME=Adwaita-dark (config.kdl `environment`),
    # but that only reaches processes niri itself spawns. nemo is D-Bus
    # activated (it ships nemo.FileManager1.service), so opening a folder via
    # xdg-open or another app's "show in file manager" starts it from the D-Bus
    # daemon's environment, which has no GTK_THEME — that window came up light.
    # GTK_THEME is also GTK's debug override; settings.ini is the supported
    # path and applies no matter how the app is launched.
    #
    # Both keys are set on purpose: gtk-theme-name picks the dark stylesheet,
    # and prefer-dark tells apps that branch on it (nemo does, for its sidebar
    # and icon rendering) which variant they are in.
    # Colloid is Material-Design-shaped, actively maintained, and — the reason it
    # was picked over the alternatives — its gtk-3.0 stylesheet carries 55 nemo
    # rules with dedicated selectors (.nemo-window, .nemo-window-pane,
    # .nemo-inactive-pane, .nemo-canvas-item, .nemo-desktop). Adwaita-dark has
    # exactly zero, which is why nemo looked like a generic GTK app under it.
    #
    # tweaks: "black" for a true-black base (matches noctalia's pure_black_dark),
    # "rimless" to drop the window outlines. themeVariants "default" is Colloid's
    # blue accent, which is also Papirus's default folder colour — so the accent
    # matches across chrome and icons without tinting either.
    theme = {
      name = "Colloid-Dark";
      package = pkgs.colloid-gtk-theme.override {
        themeVariants = [ "default" ];
        colorVariants = [ "dark" ];
        tweaks = [ "black" "rimless" ];
      };
    };

    # NOTE: gtk.iconTheme is intentionally absent. Setting it here would change
    # icons for every GTK app on the system; Papirus is scoped to nemo alone via
    # the nemo-tui wrapper at the top of this file. Adding it back here would
    # also override — and therefore silently disable — that wrapper.

    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;

    # Terminal-flavoured skin for nemo. Every rule is scoped to .nemo-window —
    # the style class nemo puts on its own toplevels — so this file can live in
    # the shared ~/.config/gtk-3.0/gtk.css without touching any other app.
    # (GTK3 only ever reads user CSS from XDG_CONFIG_HOME, so scoping by
    # selector is the only way to keep it app-local.)
    gtk3.extraCss = ''
      @define-color nemo_bg     #0b0c0e;
      @define-color nemo_bg_alt #101216;
      @define-color nemo_fg     #c5cad3;
      @define-color nemo_dim    #5c6370;
      @define-color nemo_line   #1b1e25;
      @define-color nemo_accent #7aa2f7;

      /* Monospace everywhere, square corners, no gradients or shadows. */
      .nemo-window,
      .nemo-window * {
        font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 12px;
        border-radius: 0;
        box-shadow: none;
        text-shadow: none;
        background-image: none;
      }

      .nemo-window { background-color: @nemo_bg; color: @nemo_fg; }

      /* Toolbar and path entry read as a single status line. */
      .nemo-window toolbar,
      .nemo-window .primary-toolbar {
        background-color: @nemo_bg;
        border-bottom: 1px solid @nemo_line;
        padding: 2px 4px;
        min-height: 0;
      }

      .nemo-window button {
        background-color: transparent;
        border: 1px solid transparent;
        color: @nemo_dim;
        padding: 2px 6px;
        min-height: 0;
        min-width: 0;
      }
      .nemo-window button:hover {
        color: @nemo_fg;
        background-color: @nemo_bg_alt;
        border-color: @nemo_line;
      }
      .nemo-window button:checked { color: @nemo_accent; border-color: @nemo_accent; }

      .nemo-window entry {
        background-color: @nemo_bg_alt;
        color: @nemo_fg;
        border: 1px solid @nemo_line;
        padding: 2px 6px;
        min-height: 0;
        caret-color: @nemo_accent;
      }
      .nemo-window entry:focus { border-color: @nemo_accent; }

      /* File list. Selection is a solid block, like a TUI cursor line. */
      .nemo-window treeview.view {
        background-color: @nemo_bg;
        color: @nemo_fg;
        -GtkTreeView-vertical-separator: 1;
        -GtkTreeView-horizontal-separator: 8;
        -GtkTreeView-grid-line-width: 0;
      }
      .nemo-window treeview.view:hover { background-color: @nemo_bg_alt; }
      .nemo-window treeview.view:selected,
      .nemo-window treeview.view:selected:focus,
      .nemo-window treeview.view:selected:hover {
        background-color: @nemo_accent;
        color: @nemo_bg;
      }

      .nemo-window treeview.view header button {
        background-color: @nemo_bg;
        color: @nemo_dim;
        border: none;
        border-bottom: 1px solid @nemo_line;
        font-weight: normal;
        padding: 2px 8px;
      }
      .nemo-window treeview.view header button:hover { color: @nemo_fg; }

      /* Sidebar as a split pane with a hairline divider. */
      .nemo-window .sidebar,
      .nemo-window placessidebar {
        background-color: @nemo_bg;
        color: @nemo_dim;
        border-right: 1px solid @nemo_line;
      }
      .nemo-window paned > separator {
        background-color: @nemo_line;
        min-width: 1px;
      }

      /* Tab strip: underline the active tab, nothing else. */
      .nemo-window notebook > header {
        background-color: @nemo_bg;
        border-bottom: 1px solid @nemo_line;
      }
      .nemo-window notebook > header tab {
        background-color: transparent;
        border: none;
        border-bottom: 2px solid transparent;
        color: @nemo_dim;
        padding: 3px 10px;
        min-height: 0;
      }
      .nemo-window notebook > header tab:checked {
        color: @nemo_fg;
        border-bottom-color: @nemo_accent;
      }

      /* Thin square scrollbars. */
      .nemo-window scrollbar { background-color: @nemo_bg; border: none; }
      .nemo-window scrollbar slider {
        background-color: @nemo_line;
        border: none;
        min-width: 6px;
        min-height: 6px;
        margin: 0;
      }
      .nemo-window scrollbar slider:hover { background-color: @nemo_dim; }

      .nemo-window statusbar {
        background-color: @nemo_bg;
        border-top: 1px solid @nemo_line;
        color: @nemo_dim;
        padding: 1px 8px;
        min-height: 0;
      }

      .nemo-window .nemo-canvas-item { color: @nemo_fg; }
    '';
  };

  # Qt apps ignore both of the above. Point them at the GTK theme so they follow
  # the same font instead of falling back to Qt's built-in default.
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };

  # nemo's "Open in Terminal" reads this key, and the schema default is
  # 'gnome-terminal' — a binary this system does not have, so the menu entry
  # spawned nothing and failed silently. (The schema itself resolves fine;
  # nemo's wrapper already puts cinnamon-desktop on XDG_DATA_DIRS.)
  #
  # ghostty is safe here despite being long-running: gtk-single-instance
  # defaults to "detect", which only engages for desktop-file launches. nemo
  # spawns the command directly, so each invocation gets its own process and
  # inherits the folder as its cwd — verified by spawning it and reading
  # /proc/<pid>/cwd of the child shell.
  #
  # exec-arg is what gets prepended when a *command* has to run in the
  # terminal rather than just opening one; the schema default '--' is
  # gnome-terminal syntax, and ghostty's equivalent is -e.
  dconf.settings."org/cinnamon/desktop/applications/terminal" = {
    exec = "ghostty";
    exec-arg = "-e";
  };

  # Behaviour half of the terminal look — CSS can restyle the list but only
  # these turn it into one. All values checked against org.nemo.gschema.xml.
  dconf.settings."org/nemo/preferences" = {
    default-folder-viewer = "list-view"; # columns, not a grid of big icons
    inherit-folder-viewer = true; # ...and keep it that way when navigating
    default-use-tighter-layout = true; # denser rows
    show-location-entry = true; # editable path text field over breadcrumbs
    date-format = "iso"; # 2026-08-06 12:34 instead of "Yesterday at ..."
    date-font-choice = "system-mono"; # date column in real mono, so it aligns
    size-prefixes = "base-2"; # KiB/MiB rather than KB/MB
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

  # Per-project environments: direnv loads a project's .envrc on cd and unloads
  # it on leave. Used by the CityTech member-portal checkout to pick a backend
  # environment (dev/uat/staging) without exporting secrets globally.
  #
  # nix-direnv is not needed by that project (it is a Gradle repo, not a flake),
  # but it makes `use flake` cheap and cached for anything added later.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = false; # hooked manually in ~/.zshrc, see note above
  };
  # Let Home Manager install and manage itself.
  # programs.home-manager.enable = true;
}
