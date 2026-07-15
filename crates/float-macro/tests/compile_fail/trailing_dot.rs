use rain_math_float_macro::float;

fn main() {
    // Trailing dot is not a valid float literal
    let _ = float!(5.);
}
