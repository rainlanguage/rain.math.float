# rain.math.float

Decimal floating point math implemented in Solidity/Yul.

## Context

IEEE 754 Floating point math such as is used by JavaScript is usually bad in
finance for a few reasons.

- The decimal representations of amounts and prices of things don't have exact
  representations in the underlying binary
- Mathematical nonsense like dividing by 0 gives "special" values like
  `Infinity` and `NaN` which then propagate throughout business logic rather
  than erroring
- There are more "special" values like `-0` that works just like `0` except when
  it doesn't.

This lib provides decimal floats that error upon nonsense and have no concept of
special values.

Everything you can type into a webform, or Rainlang, etc. that fits into 224 bit
coefficient with 32 bit exponent (huge values for both) will be exactly
represented.

This doesn't mean the floating point math is perfect, for example 1/3 will still
be some imprecise rounded 0.3333... value as we don't have infinite precision.

It does mean that `0.2+0.7` is `0.9` rather than `0.8999999999999999` because
the fractional values use decimal exponents rather than binary exponents.
Specifically it means that anything you can read and write as a decimal number
has an exact and distinct value onchain.

e.g. `0.2` internally is something like `2e-1` and `0.7` is `7e-1` so internally
the result is `2+7` which is `9` with an exponent of `-1`.

The following situations are handled correctly in rain floats:

- Parseable and formattable strings always map to an _exact_ value and are never
  approximated/rounded/estimated
- Two different strings representing distinct numbers always map to different
  values
  - e.g. 0e5 and 0e15 have the same numeric value and so do 10e1 and 1e2 but
    different numeric value always means different onchain value
- Two numerically different values always format canonically to two different
  strings
- Every valid string has an associated numerical onchain value
- Every numerical onchain value has a unique canonical string to represent it

## Rounding vs. erroring vs. approximating

Simply having an exact representation for every number we can write does not
mean we have exact representations for all the outputs. E.g. 1/3.

### Rounding

#### Rounding direction

The library would be non functional if we errored every time that a calculation
resulted in an imprecise answer, so instead we round as necessary.

Internal calculations all necessarily use EVM logic and so inherit all the EVM
behaviour such as rounding directions.

For example
[Solidity division docs](https://docs.soliditylang.org/en/latest/types.html#division)

> Since the type of the result of an operation is always the type of one of the
> operands, division on integers always results in an integer. In Solidity,
> division rounds towards zero. This means that
> `int256(-5) / int256(2) == int256(-2)`.

#### Approach to preserving precision

For basic mul/div/add/sub behaviour the library aligns exponents and uses 512
bit logic for intermediate calculations as much as possible to ensure the final
values are as precise as possible, despite potentially inevitable precision
loss.

For example, 1/3 yields
`0.3333333333333333333333333333333333333333333333333333333333333333333333333333`
because internally first `1` is represented as `1e152` in 512 bits and 3 becomes
`3e76` so when we divide back into 256 bits we retain the full 76 digits
representable in signed 256 bit values.

Note that 10/3 has the same coefficient as 1/3, but a different exponent so the
precision is decoupled from the scale of the result.

This approach is necessary to get useful results from scenarios such as
`( 1 / 9 ) / ( 1 / 3 ) == 0.33..` and `( 1 / 3 ) / (1 / 9) == 3` where precision
loss quickly compounds to incorrect final values.

#### Exponent underflow

When the exponent _underflows_ this means that the float is `Xe-Y` where `Y` is
some very large negative number, which means the float represents a number
extremely close to zero.

In these cases we chose to _lose precision_ by rounding towards zero rather than
erroring.

This is because in _absolute_ terms, no matter how much the exponent is
underflowing by, the numerical value is changing by increasingly negligible
amounts.

This contrasts with the overflow case (error) where the size of the exponent
overflow is losing exponentially more information if it is allowed to decapitate
the coefficient, as the exponent grows (see below).

#### Packing 2x signed ints into 1x signed int

For most low level operations where it possibly makes a difference we keep both
the exponent and signed coefficient in 2 separate `int256` values. The external
interface to the lib doesn't expose this or expect downstream dev-users to be
aware of how/when to use the unpacked form of floats.

The external interface provides a single 32 byte `Float` type that encodes the
exponent and signed coefficient together into a single value.

Necessarily there will be cases where packing 2 values into a single value of
the same size results in loss of information.

The information loss follows the rules explained here, truncation is allowed and
rounds towards zero, exponents may underflow and exponent overflows will error.

There is a "lossless" version of packing provided in the library interface that
doesn't magically resolve the information loss but converts all precision loss
into an error condition.

The lossy version simply returns a bool alongside the packed `Float` that
signifies whether the packing was lossy or not, to allow the caller to make
additional judgement calls re: when precision loss is acceptable.

#### log10, pow10, pow and sqrt

These are rounded to nearest at 41 significant digits, within proven bounds of
the true value:

- `pow10`: half a unit in the 41st digit plus 5.1662e-6 of a unit, under
  5.0000517e-41 relative.
- `log10`: half a unit in the 41st digit plus 2.245e-47 absolute.
- `pow`: 5.00006e-41 + 3N·1e-75 relative, for N the integer part of |b|.
- `sqrt`: 5.00006e-41 relative.

They are monotone within rounding error, not strictly monotone. For a < b the
order of the results can flip by exactly one unit in the last place, only when
both true values lie within the raw error of the same rounding tie, and never by
more. Callers must not rely on strict ordering at one-ulp resolution.

Exact results stay exact: powers of ten (`pow10(k)` is `10^k`, `log10(10^k)` is
`k`), integer powers, and perfect squares whose root has at most 41 significant
digits.

#### Fixed decimal conversions

There are some convenience methods in the lib for converting to/from fixed
decimal schemes, as these are by far the dominant convention in defi. Most
typical will be converting to/from an 18 decimal fixed point value, and/or
to/from token and oracle amounts that define their own decimal fixed point
scale.

The summary is that these conversions work like packing does, we preserve all
information if possible, and then may truncate/error if that is not possible due
to fundamental constraints on the information we can store.

### Erroring

#### Exponent overflow (no infinities)

When exponents _overflow_ this means the number that we are attempting to
represent cannot fit into the binary represenation that we have (assuming the
coefficient is also maximized and so we cannot shift magnitude from exponent
space to coefficient space).

In this case we error because decapitating the coefficient is an extreme loss of
information that doesn't converge on any particular value that we could round
towards.

This is _different to how floats usually work_ where a sufficiently large number
would be converted to the special `Infinity` or `-Infinity` values. We DO NOT do
this, better to error than start talking infinities when money is being handled.

#### Other overflows

Other values than the exponent can also overflow in more niche/situational
scenarios, such as the intermediate calculations moving between 512 and 256 bits
for multiplication and division. These will also error rather than
truncate/round because information loss from overflow doesn't converge to a
predictable value.

#### Uncalculable values (no NaN)

There are many cases where mathematical operations cannot produce a meaningful
finite output. The classic example is division by 0. Standard floats will try to
produce `Infinity`, `-Infinity` for `-0` division, or `NaN` for other impossible
operations.

Instead we simply error, ideally with a meaningful unique error selector so that
downstream consumers can hope to trace the cause of the error.

Other examples include:

- Taking the log of `0`
- Taking the log of a negative number
- Raising `0` to a negative number
- Internal overflows during intermediate calculations

#### Unimplemented math

There are some situations where certain operations on some numeric ranges has
not been implemented and here we error.

Most notable is that we do not currently support powers of negative number bases
as this often results in complex numbers rather than real numbers.

[rainlanguage/rain.math.float#88](https://github.com/rainlanguage/rain.math.float/issues/88)

#### Parsing/formatting issues

All parsing/formatting issues that introduce ambiguity or precision loss are
treated as an error. This is because parsing and formatting is expected to be a
"compile time" operation, and more importantly, all potentially ambiguous
aspects are in full control of the user.

There should be no situation where there is a disconnect between the value being
parsed/formatted and the provenance of the value, such that an error cannot
inform a valid revaluation by the author.

#### Lossy conversions in "lossless" mode

As mentioned above, some conversions like packing and moving to fixed decimals,
are necessarily potentially lossy operations.

When these operations are run in lossless mode they error on information loss
rather than simply return a bool, with a standard default error message.

### Approximations

The log/pow calculations are not simply truncated on precision loss, they are
inherently approximations in many cases.

`log10` takes a four figure log table value (from the tables deployed
deterministically onchain as data contracts) as a seed and refines it with a
fixed point series. It is within 2.5e-47 of the true value, and within 3e-49
relative of it for an input within a table step of a power of ten, so a log near
zero keeps its precision. A power of ten has an exact log.

`pow10` reads no tables. It computes the power in fixed point and rounds it to
41 significant digits, so it is within half a unit in the 41st digit and an
exactly representable power such as `10^2` is exact.

`pow` calculates an integer exponent exactly by squaring, and the fractional
component of a non-integer exponent as `pow10(frac(b) * log10(a))`, so it is
within about 1e-40 relative of the true value and an exactly representable power
such as `sqrt(4)` is exact.
