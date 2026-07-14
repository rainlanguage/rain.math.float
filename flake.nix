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
    flake-utils.lib.eachSystem [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ] (
      system:
      let
        pkgs = rainix.pkgs.${system};
      in
      rec {
        packages = {
          test-wasm-build = rainix.mkTask.${system} {
            name = "test-wasm-build";
            body = ''
              set -euxo pipefail
              cargo build -r --target wasm32-unknown-unknown --lib --workspace
            '';
            additionalBuildInputs = rainix.rust-build-inputs.${system};
          };

          test-js-bindings = rainix.mkTask.${system} {
            name = "test-js-bindings";
            body = ''
              set -euxo pipefail
              npm install --no-check
              npm run build
              npm test
            '';
            additionalBuildInputs =
              rainix.rust-build-inputs.${system}
              ++ rainix.node-build-inputs.${system}
              ++ [ pkgs.wasm-bindgen-cli ];
          };
        };

        devShells.default = pkgs.mkShell {
          inherit (rainix.devShells.${system}.rust-node-shell) shellHook;
          packages = [
            pkgs.wasm-bindgen-cli
            packages.test-wasm-build
            packages.test-js-bindings
          ];
          inputsFrom = [ rainix.devShells.${system}.rust-node-shell ];
        };
      }
    );
}
