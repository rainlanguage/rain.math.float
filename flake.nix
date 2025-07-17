{
  description = "Flake for development workflows.";

  inputs = {
    rainix.url = "github:rainprotocol/rainix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, rainix }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = rainix.pkgs.${system};
      in rec {
        packages = rainix.packages.${system} // {
          test-wasm-build = rainix.mkTask.${system} {
            name = "test-wasm-build";
            body = ''
              set -euxo pipefail
              cargo build -r --target wasm32-unknown-unknown --lib --workspace
            '';
          };

          test-js-bindings = rainix.mkTask.${system} {
            name = "test-js-bindings";
            body = ''
              set -euxo pipefail
              npm install --no-check
              npm run build
              npm test
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          shellHook = rainix.devShells.${system}.default.shellHook;
          packages = [ packages.test-wasm-build packages.test-js-bindings ];
          inputsFrom = [ rainix.devShells.${system}.default ];
        };
      });
}
