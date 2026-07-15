const fs = require("fs");
const { execSync } = require("child_process");

// create dist dir
fs.mkdirSync("./dist/cjs", { recursive: true });
fs.mkdirSync("./dist/esm", { recursive: true });

// build for wasm32 target
execSync("npm run build-wasm");

// generate node/web bindgens
execSync(
  `wasm-bindgen --target nodejs ./target/wasm32-unknown-unknown/release/rain_math_float_wasm.wasm --out-dir ./temp/node --out-name float`,
);
execSync(
  `wasm-bindgen --target web ./target/wasm32-unknown-unknown/release/rain_math_float_wasm.wasm --out-dir ./temp/web --out-name float`,
);

// encode wasm as base64 into a json for cjs and esm that can be natively imported
// in js modules in order to avoid using fetch or fs operations
const wasmCjsBytes = fs.readFileSync(`./temp/node/float_bg.wasm`);
fs.writeFileSync(
  `./dist/cjs/float_wbg.json`,
  JSON.stringify({
    wasm: Buffer.from(wasmCjsBytes, "binary").toString("base64"),
  }),
);
const wasmEsmBytes = fs.readFileSync(`./temp/web/float_bg.wasm`);
fs.writeFileSync(
  `./dist/esm/float_wbg.json`,
  JSON.stringify({
    wasm: Buffer.from(wasmEsmBytes, "binary").toString("base64"),
  }),
);

// prepare the dts
let dts = fs.readFileSync(`./temp/node/float.d.ts`, {
  encoding: "utf-8",
});
dts = dts.replace(
  `/* tslint:disable */
/* eslint-disable */`,
  "",
);
dts = "/* this file is auto-generated, do not modify */\n" + dts;
fs.writeFileSync(`./dist/cjs/index.d.ts`, dts);
fs.writeFileSync(`./dist/esm/index.d.ts`, dts);

// prepare cjs
let cjs = fs.readFileSync(`./temp/node/float.js`, {
  encoding: "utf-8",
});
const cjsWasmLoader = "const wasmPath = `${__dirname}/float_bg.wasm`;\n" +
  "const wasmBytes = require('fs').readFileSync(wasmPath);";
if (!cjs.includes(cjsWasmLoader)) {
  throw new Error("unexpected wasm-bindgen CommonJS loader");
}
cjs = cjs.replace(
  cjsWasmLoader,
  `
const { Buffer } = require('buffer');
const wasmB64 = require('./float_wbg.json');
const wasmBytes = Buffer.from(wasmB64.wasm, 'base64');`,
);
cjs = cjs.replace("const { TextEncoder, TextDecoder } = require(`util`);", "");
cjs = "/* this file is auto-generated, do not modify */\n" + cjs;
fs.writeFileSync(`./dist/cjs/index.js`, cjs);

// prepare esm
let esm = fs.readFileSync(`./temp/web/float.js`, {
  encoding: "utf-8",
});
const esmExports = `export { initSync, __wbg_init as default };`;
if (!esm.includes(esmExports)) {
  throw new Error("unexpected wasm-bindgen ESM exports");
}
esm = esm.replace(
  esmExports,
  `import { Buffer } from 'buffer';
import wasmB64 from './float_wbg.json';
const bytes = Buffer.from(wasmB64.wasm, 'base64');
initSync({ module: bytes });`,
);
esm = "/* this file is auto-generated, do not modify */\n" + esm;
fs.writeFileSync(`./dist/esm/index.js`, esm);

// rm temp folder
execSync("npm run rm-temp");

// check bindings for possible errors
execSync("npm run check");
