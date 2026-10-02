{
  description = "Flake for development workflows.";

  inputs = {
    rainix.url = "github:rainlanguage/rainix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      flake-utils,
      rainix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = rainix.pkgs.${system};
      in
      rec {
        packages = rainix.packages.${system};

        devShells.default = pkgs.mkShell {
          inherit (rainix.devShells.${system}.default) shellHook;
          inputsFrom = [ rainix.devShells.${system}.default ];
        };
      }
    );
}
