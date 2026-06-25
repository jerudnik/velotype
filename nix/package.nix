# Crane-based package definition for the `velotype` GPUI desktop editor.
#
# Migrated from rustPlatform.buildRustPackage to crane to match the 4nix fork
# template (split dependency layer + Cachix-friendly reproducibility). Velotype
# has no build-time git stamp, so there is no per-commit `buildMeta`; the
# dependency layer is naturally cache-stable. Linux-only: GPUI needs X11/Vulkan/
# Wayland runtime libraries, which are wrapped onto the binary at install time.
{
  lib,
  stdenv,
  craneLib,
  # Native build tools
  pkg-config,
  installShellFiles,
  makeWrapper,
  # Native/runtime inputs
  fontconfig,
  freetype,
  openssl,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxkbcommon,
  libxrandr,
  vulkan-loader,
  wayland,
  version,
}:
let
  # GPUI loads these at runtime via dlopen; they must be on LD_LIBRARY_PATH.
  runtimeLibs = [
    libx11
    libxcb
    libxcursor
    libxi
    libxkbcommon
    libxrandr
    vulkan-loader
    wayland
  ];

  # Only the workspace sources cargo needs, plus the Linux resources/icons the
  # postInstall step consumes. Keeping this tight avoids rebuilds on doc/CI edits.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      (lib.fileset.maybeMissing ../rust-toolchain.toml)
      (lib.fileset.maybeMissing ../.cargo)
      ../build.rs
      ../src
      ../assets
      ../benches
      ../resources/linux
      (lib.fileset.maybeMissing ../resources/windows)
    ];
  };

  commonArgs = {
    inherit src version;
    pname = "velotype";
    strictDeps = true;

    cargoLock = "${src}/Cargo.lock";
    # Velotype's Cargo.lock has no git dependencies, so no outputHashes needed.

    nativeBuildInputs = [
      pkg-config
      installShellFiles
      makeWrapper
    ];

    buildInputs = [
      fontconfig
      freetype
      openssl
      stdenv.cc.cc.lib
    ]
    ++ runtimeLibs;

    CARGO_PROFILE = "release";
  };

  # Build all workspace dependencies once; reused for the package.
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    cargoExtraArgs = "--locked --bin velotype";

    # Upstream's test suite contains sandbox-sensitive integration tests
    # (Mermaid/Chromium rendering, reqwest CA discovery) that fail under Nix's
    # isolated check phase. Keep the deployable GUI build focused on compilation.
    doCheck = false;

    # GPUI needs its runtime libs on LD_LIBRARY_PATH; install the desktop entry
    # and hicolor icon set so the app is launchable from a desktop environment.
    postInstall = ''
      wrapProgram "$out/bin/velotype" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}

      install -Dm0644 resources/linux/com.manyougz.Velotype.desktop \
        "$out/share/applications/com.manyougz.Velotype.desktop"
      substituteInPlace "$out/share/applications/com.manyougz.Velotype.desktop" \
        --replace-fail 'Exec=velotype %F' "Exec=$out/bin/velotype %F" \
        --replace-fail 'TryExec=velotype' "TryExec=$out/bin/velotype"
      for size in 16 32 48 64 128 256 512; do
        install -Dm0644 "assets/icon/velotype-icon-$size.png" \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/com.manyougz.Velotype.png"
      done
    '';

    meta = {
      description = "Native Rust + GPUI Markdown editor with WYSIWYG and source editing modes";
      homepage = "https://github.com/jerudnik/velotype";
      license = lib.licenses.asl20;
      mainProgram = "velotype";
      platforms = lib.platforms.linux;
    };
  }
)
