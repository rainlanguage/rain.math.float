//! Compiles the Solidity, so the bindings run over the test concretes built
//! from this source: `.cargo/config.toml` points them at the artifacts.

use std::path::Path;
use std::process::Command;

fn main() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    for watched in ["foundry.toml", "soldeer.lock", "src", "test"] {
        println!("cargo:rerun-if-changed={}", root.join(watched).display());
    }
    if !root.join("dependencies").is_dir() {
        forge(&root, &["soldeer", "install"]);
    }
    forge(&root, &["build"]);
}

fn forge(root: &Path, args: &[&str]) {
    let status = Command::new("forge")
        .args(args)
        .current_dir(root)
        .status()
        .unwrap_or_else(|e| panic!("forge {}: {e}", args.join(" ")));
    assert!(status.success(), "forge {} failed", args.join(" "));
}
