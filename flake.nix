{
  description = "Velotype, a native Rust + GPUI Markdown editor (WYSIWYG and source modes)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    crane.url = "github:ipetkov/crane";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Public, safe-to-share binary cache for prebuilt outputs.
  #
  # Create the cache with `cachix create jerudnik-velotype` and put the auth
  # token in the repo's `CACHIX_AUTH_TOKEN` secret, then paste the printed public
  # key below. Until then these lines are inert.
  nixConfig = {
    extra-substituters = [ "https://jerudnik-velotype.cachix.org" ];
    extra-trusted-public-keys = [
      "jerudnik-velotype.cachix.org-1:REPLACE_WITH_PUBLIC_KEY_FROM_cachix_create"
    ];
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        # Overlay: consumers add `inputs.velotype.overlays.default` and get
        # `pkgs.velotype`.
        overlays.default = final: prev: {
          velotype = inputs.self.packages.${final.stdenv.hostPlatform.system}.velotype;
        };

        # Home Manager module. Use as
        #   imports = [ inputs.velotype.homeManagerModules.default ];
        #   programs.velotype.enable = true;
        homeManagerModules.default = import ./nix/modules/home-manager.nix;
        homeModules.default = import ./nix/modules/home-manager.nix; # HM >= 24.11 alias
        # Back-compat aliases for downstream flakes pinned to the old names.
        homeModules.velotype = import ./nix/modules/home-manager.nix;
        homeManagerModules.velotype = import ./nix/modules/home-manager.nix;
      };

      perSystem =
        {
          self',
          system,
          ...
        }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ (import inputs.rust-overlay) ];
          };
          inherit (pkgs) lib;

          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "clippy"
              "rustfmt"
            ];
          };

          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;

          version = (craneLib.crateNameFromCargoToml { src = ./.; }).version;

          velotype = pkgs.callPackage ./nix/package.nix {
            inherit craneLib version;
          };

          runtimeLibs = [
            pkgs.libx11
            pkgs.libxcb
            pkgs.libxcursor
            pkgs.libxi
            pkgs.libxkbcommon
            pkgs.libxrandr
            pkgs.vulkan-loader
            pkgs.wayland
          ];
        in
        {
          _module.args.pkgs = pkgs;

          packages = {
            default = velotype;
            inherit velotype;
          };

          # CI gates run by `nix flake check`: verify the desktop integration and
          # that the Home Manager module evaluates. We do NOT duplicate upstream
          # clippy/rustfmt/test here (owned by upstream CI against its toolchain).
          checks = {
            desktop-entry = pkgs.runCommandLocal "velotype-desktop-entry-check" { } ''
              desktop=${velotype}/share/applications/com.manyougz.Velotype.desktop
              test -f "$desktop" || {
                echo "missing desktop entry: $desktop" >&2
                exit 1
              }

              for needle in \
                'Name=Velotype' \
                'GenericName=Markdown Editor' \
                'Exec=${velotype}/bin/velotype %F' \
                'TryExec=${velotype}/bin/velotype' \
                'Icon=com.manyougz.Velotype' \
                'Categories=Office;TextEditor;Utility;' \
                'Keywords=markdown;editor;text;notes;writing;wysiwyg;' \
                'MimeType=text/markdown;text/x-markdown;' \
                'DBusActivatable=false'; do
                grep -qxF "$needle" "$desktop" || {
                  echo "desktop entry missing expected line: $needle" >&2
                  cat "$desktop" >&2
                  exit 1
                }
              done

              for size in 16 32 48 64 128 256 512; do
                icon=${velotype}/share/icons/hicolor/''${size}x''${size}/apps/com.manyougz.Velotype.png
                test -f "$icon" || {
                  echo "missing icon: $icon" >&2
                  exit 1
                }
              done

              touch $out
            '';

            hm-module =
              (inputs.home-manager.lib.homeManagerConfiguration {
                pkgs = import inputs.nixpkgs { inherit system; };
                modules = [
                  inputs.self.homeManagerModules.default
                  {
                    home.username = "velotype-check";
                    home.homeDirectory = "/tmp/velotype-check";
                    home.stateVersion = "24.11";
                    programs.velotype = {
                      enable = true;
                      package = velotype;
                      profile = "check";
                      editor.image_paste_behavior = "copy_to_assets_folder";
                      images = {
                        asset_dir = "assets/images";
                        naming = "slug-counter";
                      };
                      keybindings.save_document = [ "ctrl-s" ];
                      keybindingProfile = "writing";
                      keybindingProfiles.writing = {
                        toggle_workspace = [ "ctrl-e" ];
                        toggle_which_key = [ "ctrl-space" ];
                      };
                      whichKey = {
                        enable = true;
                        trigger = [ "ctrl-space" ];
                      };
                      markdownExtensions = {
                        frontmatter = true;
                        wikilinks = true;
                      };
                    };
                  }
                ];
              }).activationPackage;
          };

          devShells.default = craneLib.devShell {
            checks = self'.checks;
            packages = [
              pkgs.cargo-nextest
              pkgs.cargo-audit
              pkgs.cargo-watch
              pkgs.nixfmt-rfc-style
              pkgs.pkg-config
            ];

            buildInputs = [
              pkgs.fontconfig
              pkgs.freetype
              pkgs.openssl
              pkgs.stdenv.cc.cc.lib
            ]
            ++ runtimeLibs;

            LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
            shellHook = ''
              echo "velotype dev shell — rust $(rustc --version 2>/dev/null || echo '?')"
            '';
          };

          formatter = pkgs.nixfmt-rfc-style;
        };
    };
}
