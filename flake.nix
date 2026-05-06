{
  description = "Flake for development workflows.";

  inputs = {
    rainix.url = "github:rainprotocol/rainix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, rainix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = rainix.pkgs.${system};

        decimal-float-abi = pkgs.stdenvNoCC.mkDerivation {
          pname = "rain-math-float-abi";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.foundry-bin pkgs.solc_0_8_25 ];

          FOUNDRY_SOLC = "${pkgs.solc_0_8_25}/bin/solc-0.8.25";
          FOUNDRY_OFFLINE = "true";

          buildPhase = ''
            runHook preBuild
            export HOME="$TMPDIR"
            forge build
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp out/DecimalFloat.sol/DecimalFloat.json $out/DecimalFloat.json
            cp out/TestDecimalFloat.sol/TestDecimalFloat.json $out/TestDecimalFloat.json
            runHook postInstall
          '';
        };
      in rec {
        packages = rainix.packages.${system} // {
          inherit decimal-float-abi;

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
          shellHook = rainix.devShells.${system}.default.shellHook + ''
            export RAIN_MATH_FLOAT_DECIMAL_FLOAT_ABI="$PWD/out/DecimalFloat.sol/DecimalFloat.json"
            export RAIN_MATH_FLOAT_TEST_DECIMAL_FLOAT_ABI="$PWD/out/TestDecimalFloat.sol/TestDecimalFloat.json"
          '';
          packages = [ packages.test-wasm-build packages.test-js-bindings ];
          inputsFrom = [ rainix.devShells.${system}.default ];
        };
      });
}
