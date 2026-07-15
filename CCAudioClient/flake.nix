{
  description = "CCAudioClient development shell with CraftOS-PC";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    craftos-pc-orig = pkgs.craftos-pc;

    craftos-pc-aur = pkgs.stdenv.mkDerivation rec {
      pname = "craftos-pc";
      version = "2.8.3";

      src = pkgs.fetchFromGitHub {
        owner = "MCJack123";
        repo = "craftos2";
        rev = "v${version}";
        hash = "sha256-DbxAsXxpsa42dF6DaLmgIa+Hs/PPqJ4dE97PoKxG2Ig=";
      };

      craftos2-lua = pkgs.fetchFromGitHub {
        owner = "MCJack123";
        repo = "craftos2-lua";
        rev = "v${version}";
        hash = "sha256-OCHN/ef83X4r5hZcPfFFvNJHjINCTiK+COf369/WPsA=";
      };

      craftos2-rom = pkgs.fetchFromGitHub {
        owner = "McJack123";
        repo = "craftos2-rom";
        rev = "v${version}";
        hash = "sha256-YidLt/JLwBMW0LMo5Q5PV6wGhF0J72FGX+iWYn6v0Z4=";
      };

      patches = [
        "${nixpkgs}/pkgs/by-name/cr/craftos-pc/fix-poco-header-includes.patch"
      ];

      nativeBuildInputs = [ pkgs.unzip pkgs.patchelf pkgs.pkg-config ];

      buildInputs = [
        pkgs.SDL2
        pkgs.SDL2_mixer
        pkgs.poco
        pkgs.openssl
        pkgs.ncurses
        pkgs.libpng
        pkgs.pngpp
        pkgs.libwebp
        pkgs.libx11
        pkgs.libxext
      ];

      preBuild = ''
        cp -R ${craftos2-lua}/* ./craftos2-lua/
        chmod -R u+w ./craftos2-lua

        mkdir -p icons
        unzip resources/linux-icons.zip -d icons

        make -C craftos2-lua -j$NIX_BUILD_CORES linux MYCFLAGS=-Wno-error=incompatible-pointer-types
      '';

      configurePhase = ''
              runHook preConfigure

              export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE $(pkg-config --cflags SDL2_mixer)"
              export NIX_LDFLAGS="$NIX_LDFLAGS $(pkg-config --libs SDL2_mixer)"

              ./configure --prefix=$out --with-sdl_mixer

              runHook postConfigure
            '';

      buildPhase = ''
        runHook preBuild
        make -j$NIX_BUILD_CORES
        runHook postBuild
      '';

      installPhase = ''
        mkdir -p $out/bin $out/lib $out/share/craftos $out/include

        DESTDIR=$out/bin make install

        cp craftos2-lua/src/liblua.so $out/lib/libcraftos2-lua.so
        patchelf --replace-needed craftos2-lua/src/liblua.so libcraftos2-lua.so $out/bin/craftos

        cp -R api $out/include/CraftOS-PC
        cp -R ${craftos2-rom}/* $out/share/craftos

        install -D -m 0644 icons/CraftOS-PC.desktop $out/share/applications/CraftOS-PC.desktop
        for dim in 16 24 32 48 64 96 128 256 1024; do
          if [ -f "icons/$dim.png" ]; then
            install -D -m 0644 "icons/$dim.png" "$out/share/icons/hicolor/''${dim}x''${dim}/apps/craftos.png"
          fi
        done
      '';
    };

  in {
    devShells.${system}.default = pkgs.mkShell {
      shellHook = ''
        echo "================================================="
        echo " CraftOS-PC (AUR-Ported Build with Patches)"
        echo "================================================="
      '';
    };
  };
}