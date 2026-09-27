{
  description = "Static technical blog, built with zola";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # nixpkgs 26.11 no longer supports x86_64-darwin
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);
    in
    {
      # nix build  ->  ./result with the rendered site
      packages = eachSystem (
        pkgs: _system: rec {
          blog = pkgs.callPackage ./build.nix { };
          default = blog;
        }
      );

      # nix run . (from this directory) ->  zola serve on http://localhost:1111
      # The wrapper keeps the program a single path: nix does not split extra
      # arguments out of an app's program string, it execs it verbatim.
      apps = eachSystem (
        pkgs: _system: {
          default = {
            type = "app";
            program = "${pkgs.writeShellScript "zola-serve" "exec ${lib.getExe pkgs.zola} serve \"$@\""}";
          };
        }
      );

      devShells = eachSystem (
        pkgs: _system: {
          default = pkgs.mkShell {
            packages = [ pkgs.zola ];
          };
        }
      );

      checks = eachSystem (
        _pkgs: system: {
          site = self.packages.${system}.blog;
        }
      );

      formatter = eachSystem (pkgs: _system: pkgs.nixfmt-tree);
    };
}
