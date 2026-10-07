# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
"""Second reference for crates/tests, in the standard `decimal` module.

Reads one JSON request per line on stdin and writes one JSON response per
line on stdout, so one process serves a whole proptest run. A float is
`[coefficient, exponent]` with the coefficient as a decimal string. A response
is `{"ok": value}` or `{"err": "<Solidity error name>"}`.
"""

import json
import sys
from decimal import (
    MAX_EMAX,
    MIN_EMIN,
    ROUND_CEILING,
    ROUND_DOWN,
    ROUND_FLOOR,
    ROUND_HALF_EVEN,
    ROUND_UP,
    Context,
    Decimal,
    Inexact,
    localcontext,
)

INT224_MIN = -(2**223)
INT224_MAX = 2**223 - 1
INT256_MIN = -(2**255)
INT256_MAX = 2**255 - 1
INT32_MIN = -(2**31)
INT32_MAX = 2**31 - 1
UINT256_MAX = 2**256 - 1

# Exact for every sum, product and comparison the tests send; division is
# truncated towards zero at this many digits, far past a Float's 68.
EXACT = Context(prec=1000, rounding=ROUND_DOWN, Emax=MAX_EMAX, Emin=MIN_EMIN, traps=[])
QUOTIENT = Context(prec=200, rounding=ROUND_DOWN, Emax=MAX_EMAX, Emin=MIN_EMIN, traps=[])
# The true log10, 10^x and a^b, within 1e-250 relative: log10 and exp are
# correctly rounded at 300 digits, and 10^y loses ln(10) |y| 1e-300 relative
# for |y| at most RANGE.
TRUE = Context(prec=300, rounding=ROUND_HALF_EVEN, Emax=MAX_EMAX, Emin=MIN_EMIN, traps=[])
# Past this |log10| of a result, it is past every Float on its side.
RANGE = Decimal(3000000000)


def dec(f):
    return Decimal(int(f[0])).scaleb(int(f[1]), EXACT)


def literal(s):
    # The exponent is read with int() because libmpdec turns an exponent of
    # many digits into Infinity even when they are leading zeros.
    # Zero is zero at any exponent, including one past the module's range.
    mantissa, _, exp = s.lower().partition("e")
    m = Decimal(mantissa)
    if m.is_zero():
        return Decimal(0)
    return m.scaleb(int(exp or "0"), EXACT)


def out(x):
    sign, digits, exp = x.as_tuple()
    c = int("".join(map(str, digits)) or "0")
    if sign:
        c = -c
    if c == 0:
        exp = 0
    return [str(c), exp]


def fits224(c):
    return INT224_MIN <= c <= INT224_MAX


def pack(x):
    """Truncate towards zero to the largest int224 coefficient, lift the
    exponent to the int32 floor, grow it down to the int32 ceiling.
    Returns (value, lossless) or the error name."""
    if x.is_zero():
        return Decimal(0), True
    sign, digits, exp = x.as_tuple()
    c = int("".join(map(str, digits)))
    if sign:
        c = -c
    k = 0
    while not fits224(int(Decimal(c).scaleb(-k, EXACT).to_integral_value(ROUND_DOWN, EXACT))):
        k += 1
    c = int(Decimal(c).scaleb(-k, EXACT).to_integral_value(ROUND_DOWN, EXACT))
    e = exp + k
    if e > INT32_MAX:
        grow = e - INT32_MAX
        if k == 0 and grow <= 68 and fits224(c * 10**grow):
            c, e = c * 10**grow, INT32_MAX
        else:
            return "ExponentOverflow"
    if e < INT32_MIN:
        c = int(Decimal(c).scaleb(e - INT32_MIN, EXACT).to_integral_value(ROUND_DOWN, EXACT))
        e = INT32_MIN
        if c == 0:
            return "ExponentUnderflow"
    v = Decimal(c).scaleb(e, EXACT)
    return v, v == x


def arithmetic(x):
    p = pack(x)
    if isinstance(p, str):
        return {"err": p}
    return {"ok": out(p[0])}


def int256_unit(x):
    """The exponent of x's int256 unit: its last digit when written with as
    many digits as an int256 coefficient holds, 77 or 76."""
    sign, digits, exp = x.as_tuple()
    c = int("".join(map(str, digits)))
    if sign:
        c = -c
    top = exp + len(digits)
    if INT256_MIN <= c * 10 ** (77 - len(digits)) <= INT256_MAX:
        return top - 77
    return top - 76


def rounded_sum(a, b):
    """add's sum before packing, as its NatSpec states it: the exact sum
    rounded to a multiple of the larger operand's int256 unit, towards zero
    when the signs agree and away from zero when they differ."""
    if a.is_zero():
        return b
    if b.is_zero():
        return a
    big, small = (b, a) if EXACT.abs(a) < EXACT.abs(b) else (a, b)
    unit = int256_unit(big)
    # Under one unit, small leaves the exact sum strictly within a unit of
    # big, a multiple of it: outwards when the signs agree, so towards zero is
    # big, and inwards when they differ, so away from zero is big.
    if small.adjusted() < unit:
        return big
    rounding = ROUND_DOWN if a.is_signed() == b.is_signed() else ROUND_UP
    # to_integral_value rounds without signalling Inexact.
    units = EXACT.add(a, b).scaleb(-unit, EXACT).to_integral_value(rounding, EXACT)
    return units.scaleb(unit, EXACT)


def add(a, b):
    return arithmetic(rounded_sum(a, b))


def div(a, b):
    if b.is_zero():
        return {"err": "DivisionByZero"}
    if a.is_zero():
        return {"ok": ["0", 0]}
    return arithmetic(QUOTIENT.divide(a, b))


def fixed_lossy(value, decimals):
    v, lossless = pack(Decimal(value).scaleb(-decimals, EXACT))
    return v, lossless


def to_fixed(x, decimals):
    if x < 0:
        return "NegativeFixedDecimalConversion", None
    if x.is_zero():
        return 0, True
    scaled = x.scaleb(decimals, EXACT)
    if scaled.adjusted() > 80:
        return "FixedDecimalOverflow", None
    t = scaled.to_integral_value(ROUND_DOWN, EXACT)
    if t > UINT256_MAX:
        return "FixedDecimalOverflow", None
    return int(t), t == scaled


def coefficient_exponent(f):
    return int(f[0]), int(f[1])


def canonical(f):
    """The largest |c| that fits int224 with the exponent at or above
    int32.min, for the same value."""
    c, e = coefficient_exponent(f)
    if c == 0:
        return ["0", 0]
    while e > INT32_MIN and fits224(c * 10):
        c, e = c * 10, e - 1
    return [str(c), e]


def agree(absolute, proportional, lowest, highest):
    if absolute < 0 or proportional < 0:
        return {"err": "AgreeToleranceNegative"}
    if not absolute > 0 and not proportional > 0:
        return {"err": "AgreeNoPositiveTolerance"}
    spread = rounded_sum(highest, EXACT.minus(lowest))
    anchor = max(EXACT.abs(lowest), EXACT.abs(highest))
    limit = max(absolute, EXACT.multiply(proportional, anchor))
    return {"ok": spread <= limit}


def is_odd(x):
    if x.is_zero() or x != x.to_integral_value(ROUND_DOWN, EXACT):
        return False
    _, digits, exp = x.normalize(EXACT).as_tuple()
    return exp == 0 and digits[-1] % 2 == 1


def power_of_ten(y):
    """10^y, or the error of a result past every Float."""
    if abs(y) > RANGE:
        return {"err": "ExponentOverflow" if y > 0 else "ExponentUnderflow"}
    return {"ok": out(TRUE.power(Decimal(10), y))}


def log10(a):
    if a.is_zero():
        return {"err": "Log10Zero"}
    if a < 0:
        return {"err": "Log10Negative"}
    return {"ok": out(TRUE.log10(a))}


def pow10(x):
    if x.is_zero():
        return {"ok": ["1", 0]}
    return power_of_ten(x)


def pow_(a, b):
    """a^b as LibDecimalFloat.pow documents it: a^0 is 1, 0^b is 0 or
    ZeroNegativePower, a negative a takes a whole b only and keeps its sign
    for an odd b."""
    if b.is_zero():
        return {"ok": ["1", 0]}
    if a.is_zero():
        return {"err": "ZeroNegativePower"} if b < 0 else {"ok": ["0", 0]}
    negate = False
    if a < 0:
        whole = b.normalize(EXACT)
        if whole.as_tuple().exponent < 0:
            return {"err": "PowNegativeBase"}
        negate = whole.as_tuple().exponent == 0 and whole.as_tuple().digits[-1] % 2 == 1
        a = EXACT.minus(a)
    if a == 1:
        return {"ok": ["-1" if negate else "1", 0]}
    r = power_of_ten(TRUE.multiply(b, TRUE.log10(a)))
    if negate and "ok" in r:
        r["ok"][0] = str(-int(r["ok"][0]))
    return r


def handle(req):
    op = req["op"]
    a = dec(req["a"]) if "a" in req else None
    b = dec(req["b"]) if "b" in req else None
    if op == "add":
        return add(a, b)
    if op == "sub":
        return add(a, EXACT.minus(b))
    if op == "mul":
        return arithmetic(EXACT.multiply(a, b))
    if op == "div":
        return div(a, b)
    if op == "inv":
        return div(Decimal(1), a)
    if op == "minus":
        return arithmetic(EXACT.minus(a))
    if op == "abs":
        return arithmetic(EXACT.abs(a))
    if op == "integer":
        return arithmetic(a.to_integral_value(ROUND_DOWN, EXACT))
    if op == "frac":
        return arithmetic(EXACT.subtract(a, a.to_integral_value(ROUND_DOWN, EXACT)))
    if op == "floor":
        return arithmetic(a.to_integral_value(ROUND_FLOOR, EXACT))
    if op == "ceil":
        return arithmetic(a.to_integral_value(ROUND_CEILING, EXACT))
    if op == "extremes":
        return {"ok": [[str(INT224_MAX), INT32_MAX], ["1", INT32_MIN], ["-1", INT32_MIN], [str(INT224_MIN), INT32_MAX]]}
    if op == "cmp":
        return {"ok": int(a.compare(b, EXACT))}
    if op == "from_fixed_lossy":
        v, lossless = fixed_lossy(int(req["value"]), req["decimals"])
        return {"ok": [out(v), lossless]}
    if op == "from_fixed_lossless":
        value, decimals = int(req["value"]), req["decimals"]
        v, lossless = fixed_lossy(value, decimals)
        if lossless:
            return {"ok": out(v)}
        if value > INT256_MAX and value % 10 != 0:
            return {"err": "LossyConversionToFloat"}
        return {"err": "CoefficientOverflow"}
    if op in ("to_fixed_lossy", "to_fixed_lossless"):
        r, lossless = to_fixed(a, req["decimals"])
        if lossless is None:
            return {"err": r}
        if op == "to_fixed_lossy":
            return {"ok": [str(r), lossless]}
        return {"ok": str(r)} if lossless else {"err": "LossyConversionFromFloat"}
    if op == "parse_value":
        # The value a literal denotes, packed losslessly or not at all.
        p = pack(literal(req["s"]))
        if isinstance(p, str):
            return {"err": "ExponentOverflow" if p == "ExponentOverflow" else "ParseDecimalPrecisionLoss"}
        if not p[1]:
            return {"err": "ParseDecimalPrecisionLoss"}
        return {"ok": out(p[0])}
    if op == "literal":
        return {"ok": out(literal(req["s"]))}
    if op == "log10":
        return log10(a)
    if op == "pow10":
        return pow10(a)
    if op == "pow":
        return pow_(a, b)
    if op == "pack":
        p = pack(a)
        if isinstance(p, str):
            return {"err": p}
        return {"ok": [out(p[0]), p[1]]}
    if op == "pack_lossless":
        p = pack(a)
        if p == "ExponentOverflow":
            return {"err": p}
        if isinstance(p, str) or not p[1]:
            return {"err": "CoefficientOverflow"}
        return {"ok": out(p[0])}
    if op == "pack_arithmetic":
        return arithmetic(a)
    if op == "canonical":
        return {"ok": canonical(req["a"])}
    if op == "agree":
        return agree(dec(req["absolute"]), dec(req["proportional"]), a, b)
    if op == "is_odd":
        return {"ok": is_odd(a)}
    if op == "from_fixed_unpacked":
        value, decimals = int(req["value"]), req["decimals"]
        if value > INT256_MAX:
            return {"ok": [[str(value // 10), 1 - decimals], value % 10 == 0]}
        return {"ok": [[str(value), -decimals], True]}
    raise ValueError(f"unknown op {op}")


def main():
    for line in sys.stdin:
        with localcontext(EXACT):
            EXACT.clear_flags()
            resp = handle(json.loads(line))
            if EXACT.flags[Inexact]:
                raise ArithmeticError(f"inexact exact arithmetic for {line.strip()}")
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
