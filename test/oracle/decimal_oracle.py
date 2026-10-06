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
    ROUND_DOWN,
    ROUND_FLOOR,
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


def dec(f):
    return Decimal(int(f[0])).scaleb(int(f[1]), EXACT)


def literal(s):
    # The exponent is read with int() because libmpdec turns an exponent of
    # many digits into Infinity even when they are leading zeros.
    mantissa, _, exp = s.lower().partition("e")
    return Decimal(mantissa).scaleb(int(exp or "0"), EXACT)


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


def maximize(x):
    sign, digits, exp = x.as_tuple()
    c = int("".join(map(str, digits)))
    if sign:
        c = -c
    while INT256_MIN <= c * 10 <= INT256_MAX:
        c *= 10
        exp -= 1
    return c, exp


def add(a, b):
    if a.is_zero():
        return arithmetic(b)
    if b.is_zero():
        return arithmetic(a)
    (ca, ea), (cb, eb) = maximize(a), maximize(b)
    if eb > ea:
        (ca, ea), (cb, eb) = (cb, eb), (ca, ea)
    unit = Decimal(1).scaleb(ea, EXACT)
    aligned = EXACT.divide(Decimal(cb).scaleb(eb, EXACT), unit).to_integral_value(ROUND_DOWN, EXACT)
    return arithmetic(EXACT.multiply(EXACT.add(Decimal(ca), aligned), unit))


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
