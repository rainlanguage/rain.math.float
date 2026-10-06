//! The Python `decimal` oracle (`test/oracle/decimal_oracle.py`), one
//! long-lived process per test thread so a run spawns it once per test, not
//! once per case.

use crate::reference::Dec;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

const SCRIPT: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../test/oracle/decimal_oracle.py"
);

struct Oracle {
    _child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl Oracle {
    fn spawn() -> Self {
        let mut child = Command::new("python3")
            .arg(SCRIPT)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap_or_else(|e| {
                panic!("python3 {SCRIPT} (the flake's dev shell provides python3): {e}")
            });
        let stdin = child.stdin.take().unwrap();
        let stdout = BufReader::new(child.stdout.take().unwrap());
        Self {
            _child: child,
            stdin,
            stdout,
        }
    }
}

thread_local! {
    static ORACLE: RefCell<Option<Oracle>> = const { RefCell::new(None) };
}

/// One request, one response; a dead or failing oracle panics.
pub fn ask(request: Value) -> Value {
    ORACLE.with(|cell| {
        let mut cell = cell.borrow_mut();
        let oracle = cell.get_or_insert_with(Oracle::spawn);
        writeln!(oracle.stdin, "{request}").expect("write to oracle");
        oracle.stdin.flush().expect("flush oracle");
        let mut line = String::new();
        oracle
            .stdout
            .read_line(&mut line)
            .expect("read from oracle");
        assert!(!line.is_empty(), "oracle exited on {request}");
        serde_json::from_str(&line).expect("oracle response is JSON")
    })
}

pub fn float(d: &Dec) -> Value {
    json!([d.c.to_string(), d.e])
}

pub fn to_dec(v: &Value) -> Dec {
    Dec::new(
        v[0].as_str()
            .unwrap()
            .parse::<num_bigint::BigInt>()
            .unwrap(),
        v[1].as_i64().unwrap(),
    )
}
