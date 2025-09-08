# rain.math.float

Decimal floating point math implemented in Solidity/Yul.

## Context

IEEE 754 Floating point math such as is used by JavaScript is usually bad in finance for a few reasons.

- The decimal representations of amounts and prices of things don't have exact representations in the underlying binary
- Mathematical nonsense like dividing by 0 gives "special" values like `Infinity` and `NaN` which then propagate throughout business logic rather than erroring

This lib provides decimal floats that do error upon nonsense.

Everything you can type into a webform, or Rainlang, etc. that fits into 224 bit coefficient with 32 bit exponent (huge values for both) will be exactly represented.

This doesn't mean the floating point math is perfect, for example 1/3 will still be some imprecise rounded 0.3333... value as we don't have infinite precision.

It does mean that `0.2+0.7` is `0.9` rather than `0.8999999999999999` because the fractional values use decimal exponents rather than binary exponents.

e.g. `0.2` internally is something like `2e-1` and `0.7` is `7e-1` so internally the result is `2+7` which is `9` with an exponent of `-1`.
