{
  description = "CCAudioClient development shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

    outputs = { self, nixpkgs }:
        let
          system = "x86_64-linux";
          pkgs = import nixpkgs { inherit system; };
        in
        {
          devShells.${system}.default = pkgs.mkShell {
            packages = [
              pkgs.craftos-pc
            ];

            shellHook = ''
              alias craftos="craftos --mount-ro src=src"

              echo "========================================================="
              echo " CC:Tweaked Dev Shell Active "
              echo " Write your Lua scripts inside the './src' directory."
              echo " Run 'craftos' to start the emulator."
              echo " Run 'mount src ./src' inside CraftOS to link files."
              echo "========================================================="
            '';
          };
    };
}
