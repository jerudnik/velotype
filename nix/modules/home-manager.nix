{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.velotype;
  tomlFormat = pkgs.formats.toml { };
  jsonFormat = pkgs.formats.json { };
  configRoot = if cfg.profile == null then "Velotype" else "Velotype/profiles/${cfg.profile}";

  preferences = {
    startup.open = cfg.startup.open;
    language.default_language_id = cfg.language.defaultLanguageId;
    theme.default_theme_id = cfg.theme.defaultThemeId;
    editor = {
      inherit (cfg.editor) show_table_headers image_paste_behavior;
    };
    images = {
      inherit (cfg.images) asset_dir naming;
    };
    inherit (cfg) keybindings;
    keybinding_profiles = cfg.keybindingProfiles;
    which_key = {
      inherit (cfg.whichKey) enable trigger;
    };
    markdown_extensions = {
      inherit (cfg.markdownExtensions) frontmatter wikilinks;
    };
  }
  // lib.optionalAttrs (cfg.keybindingProfile != null) {
    keybinding_profile = cfg.keybindingProfile;
  };

  configFile = tomlFormat.generate "velotype-config.toml" preferences;

  themeFiles = lib.mapAttrs' (
    name: value:
    lib.nameValuePair "${configRoot}/themes/${name}.json" {
      source =
        if builtins.isPath value || lib.isString value then
          value
        else
          jsonFormat.generate "velotype-theme-${name}.json" value;
    }
  ) cfg.themes;

  languageFiles = lib.mapAttrs' (
    name: value:
    lib.nameValuePair "${configRoot}/languages/${name}.json" {
      source =
        if builtins.isPath value || lib.isString value then
          value
        else
          jsonFormat.generate "velotype-language-${name}.json" value;
    }
  ) cfg.languages;

  velotypePackage =
    if cfg.configDir == null && cfg.profile == null then
      cfg.package
    else
      pkgs.symlinkJoin {
        name = "velotype";
        paths = [ cfg.package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          rm -f "$out/bin/velotype"
          makeWrapper ${lib.getExe cfg.package} "$out/bin/velotype" \
            ${
              lib.optionalString (
                cfg.configDir != null
              ) "--set VELOTYPE_CONFIG_DIR ${lib.escapeShellArg (toString cfg.configDir)}"
            } \
            ${lib.optionalString (
              cfg.profile != null
            ) "--set VELOTYPE_PROFILE ${lib.escapeShellArg cfg.profile}"}
        '';
      };
in
{
  options.programs.velotype = {
    enable = lib.mkEnableOption "Velotype, a native Rust/GPUI Markdown editor";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.velotype or null;
      defaultText = lib.literalExpression "pkgs.velotype";
      description = "Velotype package to install.";
    };

    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional config root exported as VELOTYPE_CONFIG_DIR for Velotype.";
    };

    profile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Velotype config profile name exported as VELOTYPE_PROFILE.";
    };

    startup.open = lib.mkOption {
      type = lib.types.enum [
        "new_file"
        "last_opened_file"
      ];
      default = "new_file";
      description = "Document opened when Velotype starts without file arguments.";
    };

    language.defaultLanguageId = lib.mkOption {
      type = lib.types.str;
      default = "en-US";
      description = "Default Velotype UI language id.";
    };

    theme.defaultThemeId = lib.mkOption {
      type = lib.types.str;
      default = "velotype";
      description = "Default Velotype theme id.";
    };

    editor.show_table_headers = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether rendered Markdown tables style their first row as headers.";
    };

    editor.image_paste_behavior = lib.mkOption {
      type = lib.types.enum [
        "none"
        "copy_to_document_folder"
        "copy_to_assets_folder"
        "copy_to_named_assets_folder"
      ];
      default = "none";
      description = "Where pasted clipboard images are copied before inserting Markdown.";
    };

    images.asset_dir = lib.mkOption {
      type = lib.types.str;
      default = "assets";
      description = "Repo/document-local directory used for copy_to_assets_folder image paste.";
    };

    images.naming = lib.mkOption {
      type = lib.types.enum [
        "original-counter"
        "slug-counter"
      ];
      default = "original-counter";
      description = "Naming strategy for copied/pasted image files.";
    };

    keybindings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        save_document = [ "ctrl-s" ];
        toggle_workspace = [ "ctrl-shift-e" ];
      };
      description = "Velotype shortcut id to key sequence list, written to config.toml.";
    };

    keybindingProfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional named keybinding profile merged over programs.velotype.keybindings.";
    };

    keybindingProfiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
      default = { };
      example = {
        writing = {
          toggle_workspace = [ "ctrl-e" ];
          toggle_which_key = [ "ctrl-space" ];
        };
      };
      description = "Named keybinding profiles available to Velotype config.toml.";
    };

    whichKey.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether Velotype's which-key shortcut overlay can be shown.";
    };

    whichKey.trigger = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ctrl-space" ];
      description = "Shortcut sequence that toggles Velotype's which-key overlay.";
    };

    markdownExtensions.frontmatter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Preserve YAML frontmatter blocks as exact raw Markdown on round-trip.";
    };

    markdownExtensions.wikilinks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Preserve Obsidian-style wikilink inline syntax on round-trip.";
    };

    themes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.path lib.types.attrs);
      default = { };
      description = "Custom theme JSON files or attribute sets installed into Velotype/themes.";
    };

    languages = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.path lib.types.attrs);
      default = { };
      description = "Custom language JSON files or attribute sets installed into Velotype/languages.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "programs.velotype.package must be set; use inputs.velotype.packages.${pkgs.stdenv.hostPlatform.system}.default when importing this module outside the Velotype flake overlay.";
      }
    ];

    home.packages = [ velotypePackage ];
    xdg.configFile = {
      "${configRoot}/config.toml".source = configFile;
    }
    // themeFiles
    // languageFiles;
  };
}
