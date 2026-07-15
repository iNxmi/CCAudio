{
  description = "CCAudioServer development shell";

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
          (pkgs.gradle.override { java = pkgs.jdk21; })
          pkgs.jdk21
        ];

        JAVA_HOME = "${pkgs.jdk21}";
      };
    };
}