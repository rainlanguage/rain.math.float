// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {
    ExponentOverflow,
    ExponentUnderflow,
    CoefficientOverflow,
    FixedDecimalOverflow,
    NegativeFixedDecimalConversion,
    LossyConversionFromFloat,
    LossyConversionToFloat,
    ZeroNegativePower,
    PowNegativeBase,
    AgreeToleranceNegative,
    AgreeNoPositiveTolerance
} from "../error/ErrDecimalFloat.sol";
import {LibDecimalFloatImplementation} from "./implementation/LibDecimalFloatImplementation.sol";

/// A decimal floating point number packed into 32 bytes. The high 32 bits are
/// a signed int32 exponent; the low 224 bits are a signed int224 coefficient.
/// The value represented is `coefficient × 10^exponent`.
///
/// Representations are non-canonical by design. Every non-zero value has an
/// infinite family of `(coefficient, exponent)` pairs that represent it — for
/// example `(5, 0)`, `(50, -1)`, and `(5000, -3)` all equal the number `5` and
/// pack to different `bytes32`. Equality between Floats is therefore numeric
/// (via `eq`, which rescales before comparing), not byte-level. `packLossy`
/// does not strip trailing decimal zeros from the coefficient; it only
/// shrinks the coefficient when it does not fit int224, or when the exponent
/// is below int32.min and shedding digits is the only way to reach the floor.
/// This is deliberate:
/// canonicalization is not free on the arithmetic hot path, and most
/// operations do not care. Consumers that need a canonical form (raw-byte
/// equality, hashing as a map key, downstream range checks) must canonicalize
/// locally at the point of use. See `LibDecimalFloatImplementation.eq` for
/// the operative numeric-equality contract.
type Float is bytes32;

/// @title LibDecimalFloat
/// Floating point math library for Rainlang.
/// Broadly implements decimal floating point math with 224 signed bits for the
/// coefficient and 32 signed bits for the exponent. Notably the implementation
/// differs from standard specifications in a few key areas:
///
/// - There is no concept of NaN or Infinity.
/// - There is no concept of rounding modes.
/// - There is no negative zero.
/// - This is a decimal floating point library, not binary.
/// - Representations are non-canonical. Multiple `(coefficient, exponent)`
///   pairs can encode the same numeric value; equality is numeric, not
///   byte-level. Canonicalization is deferred to consumers that need it
///   rather than enforced in packing, to keep the arithmetic hot path cheap.
///   See the docstring on the `Float` type for detail.
///
/// This means that operations such as divide by 0 will revert, rather than
/// produce nonsense like NaN or Infinity. This is a deliberate design choice
/// to make the library more predictable and easier to reason about as the basis
/// of a defi native smart contract language.
///
/// The reason that this is a decimal floating point system is that the inputs
/// to the system as rainlang literals are decimal values. This means that `0.1`
/// has an _exact_ representation in the system, rather than a repeating binary
/// fraction. This technically results in less precision than a binary floating
/// point system, but is much more predictable and easier to reason about in the
/// context of financial inputs and outputs, which are typically all decimal
/// values as understood by humans. However, consider that we have 224 bits of
/// precision in the coefficient, which is far more than the 53 bits of a double
/// precision floating point number regardless of binary/decimal considerations,
/// and should be more than enough for most defi use cases.
library LibDecimalFloat {
    using LibDecimalFloat for Float;

    /// A zero valued float.
    Float constant FLOAT_ZERO = Float.wrap(0);

    /// A one valued float.
    Float constant FLOAT_ONE = Float.wrap(bytes32(uint256(1)));

    /// A half valued float.
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_HALF =
        Float.wrap(bytes32(uint256(0xffffffff00000000000000000000000000000000000000000000000000000005)));

    /// A two valued float.
    Float constant FLOAT_TWO = Float.wrap(bytes32(uint256(0x02)));

    /// Largest possible positive value.
    /// type(int224).max, type(int32).max
    Float constant FLOAT_MAX_POSITIVE_VALUE =
        Float.wrap(bytes32(uint256(0x7fffffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffff)));

    /// Smallest possible positive value.
    /// 1, type(int32).min
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_MIN_POSITIVE_VALUE =
        Float.wrap(bytes32(uint256(0x8000000000000000000000000000000000000000000000000000000000000001)));

    /// Largest possible (closest to zero) negative value.
    /// -1, type(int32).min
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_MAX_NEGATIVE_VALUE =
        Float.wrap(bytes32(uint256(0x80000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff)));

    /// Smallest possible (most negative) negative value.
    /// type (int224).min, type(int32).max
    // slither-disable-next-line too-many-digits
    Float constant FLOAT_MIN_NEGATIVE_VALUE =
        Float.wrap(bytes32(uint256(0x7fffffff80000000000000000000000000000000000000000000000000000000)));

    /// Euler's number
    /// 2.718281828459045235360287471352662497757247093699959574966967627724e66, -66
    Float constant FLOAT_E =
        Float.wrap(bytes32(uint256(0xffffffbe19cfc6ef4f44cf88f14500d013df534fcaad48fca1d5ca47bea26fcc)));

    /// Pi
    /// 3.141592653589793238462643383279502884197169399375105820974944592308e66, -66
    Float constant FLOAT_PI =
        Float.wrap(bytes32(uint256(0xffffffbe1dd4c9e873614f593bba9c6007d9a7ac8d03a4b6c700a65cb537a1b4)));

    /// Convert a fixed point decimal value to a signed coefficient and exponent.
    /// The conversion can be lossy if the unsigned value is too large to fit in
    /// the signed coefficient.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @return exponent The exponent of the floating point representation.
    /// @return lossless `true` if the conversion is lossless.
    function fromFixedDecimalLossy(uint256 value, uint8 decimals) internal pure returns (int256, int256, bool) {
        unchecked {
            int256 exponent = -int256(uint256(decimals));

            // Catch an edge case where unsigned value looks like a negative
            // value when coerced.
            if (value > uint256(type(int256).max)) {
                // value is divided by 10 so won't truncate when cast.
                // forge-lint: disable-next-line(unsafe-typecast)
                return (int256(value / 10), exponent + 1, value % 10 == 0);
            } else {
                // case that would truncate is handled above.
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(unsafe-typecast, boolean-cst)
                return (int256(value), exponent, true);
            }
        }
    }

    /// Same as fromFixedDecimalLossy, but returns a Float struct instead of
    /// separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param value The fixed point decimal value to convert.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return float The Float struct containing the signed coefficient and
    /// exponent.
    /// @return lossless `true` if the conversion is lossless.
    function fromFixedDecimalLossyPacked(uint256 value, uint8 decimals) internal pure returns (Float, bool) {
        (int256 signedCoefficient, int256 exponent, bool lossless) = fromFixedDecimalLossy(value, decimals);
        (Float float, bool losslessPack) = packLossy(signedCoefficient, exponent);
        return (float, lossless && losslessPack);
    }

    /// Lossless version of `fromFixedDecimalLossy`. This will revert if the
    /// conversion is lossy.
    /// @param value As per `fromFixedDecimalLossy`.
    /// @param decimals As per `fromFixedDecimalLossy`.
    /// @return signedCoefficient As per `fromFixedDecimalLossy`.
    /// @return exponent As per `fromFixedDecimalLossy`.
    function fromFixedDecimalLossless(uint256 value, uint8 decimals) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 exponent, bool lossless) = fromFixedDecimalLossy(value, decimals);
        if (!lossless) {
            revert LossyConversionToFloat(signedCoefficient, exponent);
        }
        return (signedCoefficient, exponent);
    }

    /// Lossless version of `fromFixedDecimalLossyPacked`. This will revert if the
    /// conversion is lossy.
    /// @param value As per `fromFixedDecimalLossyPacked`.
    /// @param decimals As per `fromFixedDecimalLossyPacked`.
    /// @return float The Float struct containing the signed coefficient and
    /// exponent.
    function fromFixedDecimalLosslessPacked(uint256 value, uint8 decimals) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = fromFixedDecimalLossless(value, decimals);
        return packLossless(signedCoefficient, exponent);
    }

    /// Convert a signed coefficient and exponent to a fixed point decimal value.
    /// The conversion is impossible and will revert if the signed coefficient is
    /// negative. If the conversion overflows it will also revert.
    /// The conversion can be lossy if the floating point representation is not
    /// able to fit in the fixed point representation, and will truncate
    /// precision.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @param exponent The exponent of the floating point representation.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value.
    /// @return lossless `true` if the conversion is lossless.
    function toFixedDecimalLossy(int256 signedCoefficient, int256 exponent, uint8 decimals)
        internal
        pure
        returns (uint256, bool)
    {
        // The output type is uint256, so we can't represent negative numbers.
        if (signedCoefficient < 0) {
            revert NegativeFixedDecimalConversion(signedCoefficient, exponent);
        }
        // Zero is always 0 and neither exponent nor decimals matter.
        else if (signedCoefficient == 0) {
            // The literal is the bool this function returns, not a condition operand.
            //forge-lint: disable-next-line(boolean-cst)
            return (0, true);
        } else {
            // Safe to do this conversion because we revert above on negative.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 unsignedCoefficient = uint256(signedCoefficient);
            int256 finalExponent;

            // Ye olde "safe math" to give a better error if this edge case
            // overflow is ever hit. Normal use should never overflow here.
            unchecked {
                finalExponent = exponent + int256(uint256(decimals));
                if (finalExponent < exponent) {
                    revert ExponentOverflow(signedCoefficient, exponent);
                }
            }

            uint256 scale;
            uint256 fixedDecimal;
            if (finalExponent < 0) {
                unchecked {
                    // Every possible value rounds to 0 if the exponent is less
                    // than -77. This is always lossy as we know the value is
                    // not zero in real.
                    if (finalExponent < -77) {
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (0, false);
                    }

                    // At this point, scale cannot revert, so it is safe to do
                    // this unchecked.
                    // finalExponent is negative here so making it absolute will
                    // always fit in uint256.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    scale = 10 ** uint256(-finalExponent);
                    fixedDecimal = unsignedCoefficient / scale;

                    // Slither false positive because we're explicitly checking
                    // for the lossiness that it warns about.
                    //slither-disable-next-line divide-before-multiply
                    return (fixedDecimal, fixedDecimal * scale == unsignedCoefficient);
                }
            } else if (finalExponent > 0) {
                unchecked {
                    // The smallest non-zero coefficient times 10^78 already
                    // exceeds uint256.max, so any finalExponent > 77 cannot
                    // be represented as a uint256.
                    if (finalExponent > 77) {
                        revert FixedDecimalOverflow(signedCoefficient, exponent, decimals);
                    }

                    // finalExponent in [1, 77] keeps 10 ** finalExponent
                    // within uint256.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    scale = 10 ** uint256(finalExponent);

                    // Pre-check the multiplication; the alternative is a
                    // bare Panic(0x11) from checked-math, which carries no
                    // structured information about which inputs overflowed.
                    if (unsignedCoefficient > type(uint256).max / scale) {
                        revert FixedDecimalOverflow(signedCoefficient, exponent, decimals);
                    }
                    fixedDecimal = unsignedCoefficient * scale;
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (fixedDecimal, true);
                }
            } else {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                return (unsignedCoefficient, true);
            }
        }
    }

    /// Same as toFixedDecimalLossy, but accepts a Float struct instead of
    /// separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value.
    /// @return lossless `true` if the conversion is lossless.
    function toFixedDecimalLossy(Float float, uint8 decimals) internal pure returns (uint256, bool) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        return toFixedDecimalLossy(signedCoefficient, exponent, decimals);
    }

    /// Lossless version of `toFixedDecimalLossy`. This will revert if the
    /// conversion is lossy.
    /// @param signedCoefficient As per `toFixedDecimalLossy`.
    /// @param exponent As per `toFixedDecimalLossy`.
    /// @param decimals As per `toFixedDecimalLossy`.
    /// @return value As per `toFixedDecimalLossy`.
    function toFixedDecimalLossless(int256 signedCoefficient, int256 exponent, uint8 decimals)
        internal
        pure
        returns (uint256)
    {
        (uint256 value, bool lossless) = toFixedDecimalLossy(signedCoefficient, exponent, decimals);
        if (!lossless) {
            revert LossyConversionFromFloat(signedCoefficient, exponent);
        }
        return value;
    }

    /// Same as toFixedDecimalLossless, but accepts a Float struct instead of
    /// separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent.
    /// @param decimals The number of decimals in the fixed point representation.
    /// e.g. If 1e18 represents 1 this would be 18 decimals.
    /// @return value The fixed point decimal value.
    function toFixedDecimalLossless(Float float, uint8 decimals) internal pure returns (uint256) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        return toFixedDecimalLossless(signedCoefficient, exponent, decimals);
    }

    /// Pack a signed coefficient and exponent into a single `Float`.
    /// Clearly this involves fitting 64 bytes into 32 bytes, so there will be
    /// data loss.
    ///
    /// The coefficient is divided by ten (rounding towards zero) and the
    /// exponent raised by one, as many times as it takes to fit the coefficient
    /// in int224 AND the exponent in int32. Both directions of the trade are
    /// the same operation, so the packing never gives up on the exponent while
    /// it still has coefficient digits to spend: a value whose exponent is
    /// below the floor is brought up to the floor by shedding its low digits,
    /// and only when every digit has been shed (the value is smaller than any
    /// representable Float) does it become `FLOAT_ZERO`. This matches the
    /// README's stated policy for underflow: lose precision by rounding towards
    /// zero rather than erroring, because in absolute terms the amount lost is
    /// negligible. The inverse trade covers an exponent above the ceiling: the
    /// coefficient is multiplied by ten and the exponent lowered by one until
    /// the exponent is int32.max, which is exact, so `1` at int32.max + 1 packs
    /// losslessly as `10` at int32.max. Multiplying grows the coefficient, so
    /// this only works while it has int224 headroom; exponent OVERFLOW reverts
    /// when it does not.
    ///
    /// The packing is lossless if and only if every digit shed was a zero, so
    /// `lossless` reports whether the packed value is numerically equal to the
    /// input, not whether the input already fitted. A coefficient that does not
    /// fit int224 but is an exact multiple of the power of ten it was divided
    /// by packs losslessly. This matters at the exponent floor in particular:
    /// the arithmetic operations maximise their operands (multiplying the
    /// coefficient up to ~1e76 and lowering the exponent to match), so a value
    /// AT the floor reaches this function as a huge coefficient dozens of
    /// exponent steps BELOW the floor, and the trailing zeros maximisation
    /// added are exactly what must be shed to get back to it.
    /// @param signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @param exponent The exponent of the floating point representation.
    /// @return float The packed representation of the signed coefficient and
    /// exponent.
    /// @return lossless True if the packed value is numerically equal to the
    /// input, false otherwise.
    function packLossy(int256 signedCoefficient, int256 exponent) internal pure returns (Float float, bool lossless) {
        unchecked {
            int256 initialSignedCoefficient = signedCoefficient;
            int256 initialExponent = exponent;

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            bool fits = int224(signedCoefficient) == signedCoefficient;

            if (!fits) {
                if (signedCoefficient / 1e72 != 0) {
                    signedCoefficient /= 1e5;
                    exponent += 5;
                }

                // truncation here is intentional if it happens as that is what we
                // are testing for.
                // forge-lint: disable-next-line(unsafe-typecast)
                while (int224(signedCoefficient) != signedCoefficient) {
                    signedCoefficient /= 10;
                    ++exponent;
                }
            } else {
                if (signedCoefficient == 0) {
                    // The literal is the bool this function returns, not a condition operand.
                    //forge-lint: disable-next-line(boolean-cst)
                    return (FLOAT_ZERO, true);
                }
            }

            // truncation here is intentional if it happens as that is what we
            // are testing for.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (int32(exponent) != exponent) {
                // Shedding raises the exponent by at most ten digits, so an
                // exponent past the ceiling started positive, and one that
                // started positive and is out of range is past the ceiling,
                // or wrapped through int256.max by the unchecked shedding.
                if (initialExponent > 0) {
                    // Lower the exponent by multiplying the coefficient by ten
                    // per step, which is exact, while int224 has the headroom.
                    // A coefficient shed to fit int224 has none, and a non-zero
                    // int224 has at most 68 digits so an excess of 68 or more
                    // never has it. Either way the magnitude exceeds every
                    // representable Float.
                    int256 excess = exponent - type(int32).max;
                    if (!fits || excess > 67) {
                        revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                    }
                    // excess is in [1, 67] so 10 ** excess fits int256 and the
                    // casts cannot truncate.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    int256 scale = int256(10 ** uint256(excess));
                    // Nothing was shed, so the initial coefficient is the one to
                    // lift.
                    if (
                        initialSignedCoefficient > type(int224).max / scale
                            || initialSignedCoefficient < type(int224).min / scale
                    ) {
                        revert ExponentOverflow(initialSignedCoefficient, initialExponent);
                    }
                    signedCoefficient = initialSignedCoefficient * scale;
                    exponent = type(int32).max;
                } else {
                    // The exponent is below the int32 floor. Every division of the
                    // coefficient by ten raises the exponent by one, so the
                    // shortfall is exactly the number of digits to shed. The
                    // coefficient fits int224 here, so it has at most 68 decimal
                    // digits and a shortfall of 68 or more sheds every one of
                    // them: that is zero without computing it. `exponent` is
                    // negative here and below int32.min, so the subtraction cannot
                    // overflow and the shortfall is positive.
                    int256 shortfall = int256(type(int32).min) - exponent;
                    if (shortfall > 67) {
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (FLOAT_ZERO, false);
                    }
                    // shortfall is in [1, 67] so 10 ** shortfall fits int256 and the
                    // casts cannot truncate.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    signedCoefficient /= int256(10 ** uint256(shortfall));
                    if (signedCoefficient == 0) {
                        // Every digit was shed: the value is smaller in magnitude
                        // than any representable Float, so this is the underflow
                        // zero and it is not a lossless conversion.
                        // The literal is the bool this function returns, not a condition operand.
                        //forge-lint: disable-next-line(boolean-cst)
                        return (FLOAT_ZERO, false);
                    }
                    exponent = type(int32).min;
                }
            }

            // Lossless iff every digit shed was a zero, which is iff the
            // original coefficient is an exact multiple of ten to the number of
            // digits shed. Shedding only raises the exponent and lifting only
            // lowers it, and never both, so an exponent at or below the initial
            // one shed nothing. Otherwise the number shed is the rise, which is
            // in [1, 76] for any non-zero result (an int256 has at most 77
            // digits and at least one survived), so the power fits int256.
            if (exponent <= initialExponent) {
                // The literal is the bool this function returns, not a condition operand.
                //forge-lint: disable-next-line(boolean-cst)
                lossless = true;
            } else {
                // The rise is in [1, 76] so the casts cannot truncate.
                // forge-lint: disable-next-line(unsafe-typecast)
                lossless = initialSignedCoefficient % int256(10 ** uint256(exponent - initialExponent)) == 0;
            }

            // Need a mask to zero out the bits that could be set to 1 if the
            // coefficient is negative.
            uint256 mask = type(uint224).max;
            assembly ("memory-safe") {
                float := or(and(signedCoefficient, mask), shl(0xe0, exponent))
            }
        }
    }

    /// Lossless version of `packLossy`. This will revert if the conversion is
    /// lossy.
    /// @param signedCoefficient As per `packLossy`.
    /// @param exponent As per `packLossy`.
    /// @return float As per `packLossy`.
    function packLossless(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        if (!lossless) {
            revert CoefficientOverflow(signedCoefficient, exponent);
        }
        return c;
    }

    /// Variant of `packLossy` used as the finaliser of every arithmetic
    /// operation. Tolerates coefficient truncation (which preserves the order
    /// of magnitude) but reverts on exponent underflow (which silently
    /// replaces the value by `FLOAT_ZERO`, losing the magnitude entirely).
    /// Distinguishes the two `lossless = false` modes from `packLossy` by the
    /// returned float: `packLossy` only returns `FLOAT_ZERO` for the underflow
    /// case when `lossless` is false (digit shedding stops at int32.min with a
    /// non-zero coefficient whenever one is reachable, so a zero from a
    /// non-zero input means every digit was shed and the magnitude is gone).
    function packArithmeticResult(int256 signedCoefficient, int256 exponent) internal pure returns (Float) {
        (Float c, bool lossless) = packLossy(signedCoefficient, exponent);
        if (!lossless && Float.unwrap(c) == bytes32(0)) {
            revert ExponentUnderflow(signedCoefficient, exponent);
        }
        return c;
    }

    /// Unpack a packed bytes32 into a signed coefficient and exponent. This is
    /// the inverse of `pack`.
    /// @param float The packed representation of the signed coefficient and
    /// exponent.
    /// @return signedCoefficient The signed coefficient of the floating point
    /// representation.
    /// @return exponent The exponent of the floating point representation.
    function unpack(Float float) internal pure returns (int256 signedCoefficient, int256 exponent) {
        uint256 mask = type(uint224).max;
        assembly ("memory-safe") {
            signedCoefficient := signextend(27, and(float, mask))
            exponent := sar(0xe0, float)
        }
    }

    /// Canonicalize a Float to a unique byte representation per numeric value.
    /// Floats are non-canonical by design (see the docstring on the `Float`
    /// type): multiple `(coefficient, exponent)` pairs encode the same number
    /// and equality is numeric (`eq`) rather than byte-level. This function
    /// returns the single representative whose magnitude-maximised packing is
    /// stable, so two Floats are numerically equal iff their canonical forms
    /// are byte-equal (`Float.unwrap(a.canonicalize()) == Float.unwrap(b.canonicalize())`).
    /// Intended for consumers that need raw-byte equality: `mapping(Float => X)`
    /// keys, hashing, set membership, content-addressed storage.
    ///
    /// The chosen representative has the largest `|coefficient|` that fits
    /// int224 subject to the exponent staying `>= type(int32).min`, reached by
    /// scaling the coefficient up by ten directly within those bounds. This
    /// never reverts for any valid input Float: scaling simply stops at the
    /// limit. `canonicalize` is idempotent and value-preserving (the result is
    /// `eq` to the input).
    /// @param float The float to canonicalize.
    /// @return The canonical representative of the float's numeric value.
    function canonicalize(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        if (signedCoefficient == 0) {
            return FLOAT_ZERO;
        }
        unchecked {
            while (exponent > type(int32).min) {
                int256 trySignedCoefficient = signedCoefficient * 10;
                // int224 overflow is the termination condition for the scaling
                // loop, not a bug. The cast back is compared against the
                // pre-cast value to detect that overflow.
                // forge-lint: disable-next-line(unsafe-typecast)
                if (int224(trySignedCoefficient) != trySignedCoefficient) {
                    break;
                }
                signedCoefficient = trySignedCoefficient;
                exponent -= 1;
            }
        }
        return packLossless(signedCoefficient, exponent);
    }

    /// Same as add, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    /// @return The sum of the two floats.
    function add(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.add(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        // Addition can be lossy.

        Float c = packArithmeticResult(signedCoefficient, exponent);
        return c;
    }

    /// Subtract float b from float a.
    ///
    /// This is effectively shorthand for adding the two floats with the second
    /// float negated. Therefore, the same caveats apply as for `add`.
    /// @param a The float to subtract from.
    /// @param b The float to subtract.
    /// @return The difference of the two floats (a - b).
    function sub(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficientC, int256 exponentC) =
            LibDecimalFloatImplementation.sub(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        // Subtraction can be lossy.

        Float c = packArithmeticResult(signedCoefficientC, exponentC);
        return c;
    }

    /// Same as minus, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    /// @return The negated float.
    function minus(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        // Minus is a lossy operation due to the asymmetry of signed integers.

        Float result = packArithmeticResult(signedCoefficient, exponent);
        return result;
    }

    /// Returns the absolute value of a float.
    /// Identity if non-negative, negated if negative. Max negative signed value
    /// for the coefficient will be shifted one OOM so that it can be negated to
    /// a positive value.
    ///
    /// https://speleotrove.com/decimal/daops.html#refabs
    /// > abs takes one operand. If the operand is negative, the result is the
    /// > same as using the minus operation on the operand. Otherwise, the result
    /// > is the same as using the plus operation on the operand.
    /// @param float The float to take the absolute value of.
    /// @return The absolute value of the float.
    function abs(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();

        if (signedCoefficient < 0) {
            (signedCoefficient, exponent) = LibDecimalFloatImplementation.minus(signedCoefficient, exponent);
        }

        // At the limit of signed values there is the potential for a lossy
        // conversion when negating.
        Float result = packArithmeticResult(signedCoefficient, exponent);
        return result;
    }

    /// https://speleotrove.com/decimal/daops.html#refmult
    /// > multiply takes two operands. If either operand is a special value then
    /// > the general rules apply.
    /// >
    /// > Otherwise, the operands are multiplied together
    /// > (‘long multiplication’), resulting in a number which may be as long as
    /// > the sum of the lengths of the two operands, as follows:
    /// >
    /// > - The coefficient of the result, before rounding, is computed by
    /// >   multiplying together the coefficients of the operands.
    /// > - The exponent of the result, before rounding, is the sum of the
    /// >   exponents of the two operands.
    /// > - The sign of the result is the exclusive or of the signs of the
    /// >   operands.
    /// >
    /// > The result is then rounded to precision digits if necessary, counting
    /// > from the most significant digit of the result.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    /// @return The product of the two floats.
    function mul(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.mul(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        // Multiplication is typically lossless, but can be lossy in edge cases.
        Float c = packArithmeticResult(signedCoefficient, exponent);
        return c;
    }

    /// Same as `div`, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The Float struct containing the signed coefficient and
    /// exponent of the first floating point number.
    /// @param b The Float struct containing the signed coefficient and
    /// exponent of the second floating point number.
    /// @return The quotient of the two floats (a / b).
    function div(Float a, Float b) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        (int256 signedCoefficient, int256 exponent) =
            LibDecimalFloatImplementation.div(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
        // Division is often lossy because it is very easy to end up with
        // infinite decimal representations.
        Float c = packArithmeticResult(signedCoefficient, exponent);
        return c;
    }

    /// Same as inv, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    /// @return The multiplicative inverse (1 / float).
    function inv(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.inv(signedCoefficient, exponent);
        Float result = packArithmeticResult(signedCoefficient, exponent);
        return result;
    }

    /// Same as eq, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if the two floats are numerically equal.
    function eq(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return LibDecimalFloatImplementation.eq(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric less than for floats.
    /// A float is less than another if its numeric value is less than the other.
    /// For example, 1e2 is less than 1e3, and 1e2 is less than 2e2.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if a is less than b.
    function lt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return LibDecimalFloatImplementation.lt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric greater than for floats.
    /// A float is greater than another if its numeric value is greater than the
    /// other. For example, 1e3 is greater than 1e2, and 2e2 is greater than 1e2.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if a is greater than b.
    function gt(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return LibDecimalFloatImplementation.gt(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric less than or equal to for floats.
    /// A float is less than or equal to another if its numeric value is less
    /// than or equal to the other. For example, 1e2 is less than or equal to 1e3
    /// and 1e2 is less than or equal to 1e2.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if a is less than or equal to b.
    function lte(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return LibDecimalFloatImplementation.lte(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Numeric greater than or equal to for floats.
    /// A float is greater than or equal to another if its numeric value is
    /// greater than or equal to the other. For example, 1e3 is greater than or
    /// equal to 1e2 and 1e2 is greater than or equal to 1e2.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return True if a is greater than or equal to b.
    function gte(Float a, Float b) internal pure returns (bool) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (int256 signedCoefficientB, int256 exponentB) = b.unpack();
        return LibDecimalFloatImplementation.gte(signedCoefficientA, exponentA, signedCoefficientB, exponentB);
    }

    /// Integer component of a float.
    /// For positive numbers this is the floor, for negative numbers this is
    /// the ceiling.
    /// @param float The float to return the integer part of.
    /// @return The integer component of the float.
    function integer(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        //slither-disable-next-line unused-return
        (int256 i,) = LibDecimalFloatImplementation.intFrac(signedCoefficient, exponent);
        Float result = packArithmeticResult(i, exponent);
        return result;
    }

    /// Fractional component of a float.
    /// @param float The float to return the fractional part of.
    /// @return The fractional component of the float.
    function frac(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        //slither-disable-next-line unused-return
        (, int256 fraction) = LibDecimalFloatImplementation.intFrac(signedCoefficient, exponent);
        Float result = packArithmeticResult(fraction, exponent);
        return result;
    }

    /// Smallest integer value less than or equal to the float.
    /// @param float The float to floor.
    /// @return The floored float.
    function floor(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        // If the exponent is 0 or greater then the float is already an integer.
        if (exponent >= 0) {
            return float;
        }
        (int256 i, int256 fraction) = LibDecimalFloatImplementation.intFrac(signedCoefficient, exponent);
        if (signedCoefficient < 0 && fraction != 0) {
            // If the float is negative and has a fractional part, we need to
            // subtract 1 from the characteristic to floor it.
            (i, exponent) = LibDecimalFloatImplementation.sub(i, exponent, 1e76, -76);
        }
        Float result = packArithmeticResult(i, exponent);
        return result;
    }

    /// Smallest integer value greater than or equal to the float.
    /// @param float The float to ceil.
    /// @return The ceiled float.
    function ceil(Float float) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        // If the exponent is 0 or greater then the float is already an integer.
        if (exponent >= 0) {
            return float;
        }
        (int256 i, int256 fraction) = LibDecimalFloatImplementation.intFrac(signedCoefficient, exponent);

        // If the fraction is 0, then the float is already an integer.
        if (fraction == 0) {
            return float;
        }
        // Truncate the fractional part when exponent < 0:
        //   fraction < 0 (input < 0) → truncation towards zero increases the value (correct ceil).
        //   fraction == 0 → value is already an integer.
        //   fraction > 0 (input > 0) → truncation decreases the value, so add 1 to round up.
        else if (fraction > 0) {
            (i, exponent) = LibDecimalFloatImplementation.add(i, exponent, 1e76, -76);
        }

        Float result = packArithmeticResult(i, exponent);
        return result;
    }

    /// Same as `pow10`, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param float The Float struct containing the signed coefficient and
    /// exponent of the floating point number.
    /// The tables address is unused, and kept so that callers need not change.
    /// @return The result of 10^float, rounded to nearest at 41 significant
    /// digits, within half a unit in the 41st digit plus 3.28e-8 of a unit,
    /// under 5.0000004e-41 relative. A result below 1e-2147483608 sheds digits
    /// to lift its exponent to the int32 floor, so its bound adds
    /// 1e-2147483648 absolute, and below 1e-2147483648 it reverts
    /// `ExponentUnderflow`. Monotone within rounding error: for
    /// x < y the results can be out of order by exactly one unit in the last
    /// place, only when both true values lie within the raw error of the same
    /// rounding tie, and never by more. Callers must not rely on strict
    /// ordering at one-ulp resolution. 10^k is exactly 10^k for an integer k.
    function pow10(Float float, address) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = float.unpack();
        // A zero of any exponent, which the integer part below cannot rescale.
        if (signedCoefficient == 0) {
            return FLOAT_ONE;
        }
        // An integer part past int256 is over 5.7e76, far past the range on
        // the side of its sign.
        if (
            exponent > 76
                || (exponent > 0
                    // exponent is in [1, 76] here, so 10 ** exponent fits int256.
                    // forge-lint: disable-next-line(unsafe-typecast)
                    && (signedCoefficient > type(int256).max / int256(10 ** uint256(exponent))
                        // forge-lint: disable-next-line(unsafe-typecast)
                        || signedCoefficient < type(int256).min / int256(10 ** uint256(exponent))))
        ) {
            if (signedCoefficient < 0) {
                revert ExponentUnderflow(signedCoefficient, exponent);
            }
            revert ExponentOverflow(signedCoefficient, exponent);
        }
        (signedCoefficient, exponent) = LibDecimalFloatImplementation.pow10(signedCoefficient, exponent);
        return packArithmeticResult(signedCoefficient, exponent);
    }

    /// Same as log10, but accepts a Float struct instead of separate values.
    /// Costs more gas but helps mitigate stack depth issues, and is more
    /// ergonomic for the caller.
    /// @param tablesDataContract Unused, and kept so that callers need not
    /// change.
    /// @param a The float to log10.
    /// @return The base-10 logarithm of a, rounded to nearest at 41
    /// significant digits, within half a unit in the 41st digit plus 2e-50
    /// absolute. Monotone within rounding error: for x < y the results can be
    /// out of order by exactly one unit in the last place, only when both
    /// true values lie within the raw error of the same rounding tie, and
    /// never by more. Callers must not rely on strict ordering at one-ulp
    /// resolution. log10(10^k) is exactly k.
    function log10(Float a, address tablesDataContract) internal pure returns (Float) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        (signedCoefficient, exponent) =
            LibDecimalFloatImplementation.log10(tablesDataContract, signedCoefficient, exponent);
        // We don't care if log10 is lossy because it's an approximation anyway.
        Float result = packArithmeticResult(signedCoefficient, exponent);
        return result;
    }

    /// a^b = a^int(b) * 10^(frac(b) * log10(a))
    ///
    /// The integer part of `b` is exact, by squaring. The fractional part is
    /// computed in fixed point.
    ///
    /// The final product, including a^1, is rounded to nearest at 41
    /// significant digits, half away from zero. For N the integer part of
    /// |b|, the result is within 5.0000004e-41 + 3N 1e-75 relative of the true
    /// value:
    /// - The leg keeps pow10's guard digits. Their 3.28e-48 relative, plus
    ///   log10Unrounded's 2e-50 times a fraction below 1 and ln 10, puts
    ///   it within 3.33e-48 relative of 10^(frac(b) log10(a)).
    /// - Every multiply and the inverse truncate toward zero by under 1e-75,
    ///   and squaring to the Nth power weights them by at most 2N in all, so
    ///   the integer part is within 2N 1e-75 relative, and its product with
    ///   the leg adds 1e-75 more. With N 1 the integer part is a itself.
    /// - Rounding adds half a unit in the 41st digit, at most 5e-41 of the
    ///   product. A product that rounding would carry above the largest
    ///   Float is instead truncated to int224, under 1e-67 relative.
    /// - A result below 1e-2147483608 sheds digits to lift its exponent to
    ///   the int32 floor, so its bound adds 1e-2147483648 absolute. Below
    ///   1e-2147483648 it reverts `ExponentUnderflow`.
    /// Monotone within rounding error: for b < c, a^b and a^c can be out of
    /// order by exactly one unit in the last place, only when both true
    /// values lie within the larger raw error, 3.33e-48 + 3N 1e-75 relative,
    /// of the same rounding tie, and never by more. Callers must not rely on
    /// strict ordering at one-ulp resolution.
    /// Exact results stay exact: a power with at most 41 significant digits,
    /// integer or fractional such as 4^0.5.
    ///
    /// Doesn't lose precision due to the exponent, for a wide range of
    /// exponents.
    ///
    /// A negative `a` is supported only for a whole `b`, where the result is
    /// `(-a)^b` with the sign of `a` kept when `b` is odd. A negative `a` with a
    /// fractional `b` reverts `PowNegativeBase`.
    /// @param a The float `a` in `a^b`.
    /// @param b The float `b` in `a^b`.
    /// @param tablesDataContract Unused, and kept so that callers need not
    /// change.
    /// @return The result of a^b.
    function pow(Float a, Float b, address tablesDataContract) internal pure returns (Float) {
        (int256 signedCoefficientA, int256 exponentA) = a.unpack();
        (signedCoefficientA, exponentA) = powUnrounded(signedCoefficientA, exponentA, b, tablesDataContract);
        return packRoundedSignificant(signedCoefficientA, exponentA);
    }

    /// `pow` before rounding and packing, so a negative base and an odd power
    /// are negated unpacked: int224.min at int32.max has no packed negation.
    function powUnrounded(int256 signedCoefficientA, int256 exponentA, Float b, address tablesDataContract)
        private
        pure
        returns (int256, int256)
    {
        if (b.isZero()) {
            (signedCoefficientA, exponentA) = FLOAT_ONE.unpack();
            return (signedCoefficientA, exponentA);
        } else if (signedCoefficientA <= 0) {
            if (signedCoefficientA == 0) {
                if (b.lt(FLOAT_ZERO)) {
                    // If b is negative, and a is 0, so we revert.
                    revert ZeroNegativePower(b);
                }

                // If a is zero, then a^b is always zero, regardless of b.
                // This is a special case because log10(0) is undefined.
                (signedCoefficientA, exponentA) = FLOAT_ZERO.unpack();
                return (signedCoefficientA, exponentA);
            } else {
                // A negative base has a real power only for a whole exponent:
                // (-a)^b is a^b, negated when b is odd.
                if (!b.frac().isZero()) {
                    revert PowNegativeBase(signedCoefficientA, exponentA);
                }
                (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.minus(signedCoefficientA, exponentA);
                (signedCoefficientA, exponentA) = powUnrounded(signedCoefficientA, exponentA, b, tablesDataContract);
                if (b.isOdd()) {
                    (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.minus(signedCoefficientA, exponentA);
                }
                return (signedCoefficientA, exponentA);
            }
        }
        // 1^b is 1 for every b, including one too large for the integer leg.
        else if (isOne(signedCoefficientA, exponentA)) {
            (signedCoefficientA, exponentA) = FLOAT_ONE.unpack();
            return (signedCoefficientA, exponentA);
        }
        // Handle identity case for positive values of a, i.e. a^1.
        else if (b.eq(FLOAT_ONE)) {
            return (signedCoefficientA, exponentA);
        }

        // Uses LibDecimalFloatImplementation directly (rather than the packed
        // Float API) to avoid repeated pack/unpack overhead in the squaring
        // loop and to preserve unnormalized intermediates.
        int256 exponentB;
        int256 fractionB;
        uint256 exponentBInteger;
        {
            int256 signedCoefficientB;
            (signedCoefficientB, exponentB) = b.unpack();
            if (signedCoefficientB < 0) {
                // a^b is (1/a)^-b. The inverse stays unpacked: packed, the
                // inverse of a value near the top of the range underflows even
                // when the power is representable. -b stays unpacked too, as
                // the most negative Float does not pack negated.
                (signedCoefficientA, exponentA) = LibDecimalFloatImplementation.inv(signedCoefficientA, exponentA);
                signedCoefficientB = -signedCoefficientB;
            }
            int256 integerB;
            (integerB, fractionB) = LibDecimalFloatImplementation.intFrac(signedCoefficientB, exponentB);
            revertIfIntegerBPastInt256(signedCoefficientA, exponentA, integerB, exponentB);
            exponentBInteger = uint256(LibDecimalFloatImplementation.withTargetExponent(integerB, exponentB, 0));
        }

        // Exponentiation by squaring.
        (int256 signedCoefficientResult, int256 exponentResult) = (1, 0);
        {
            (int256 signedCoefficientBase, int256 exponentBase) = (signedCoefficientA, exponentA);
            while (exponentBInteger >= 1) {
                if (exponentBInteger & 0x01 == 0x01) {
                    (signedCoefficientResult, exponentResult) = LibDecimalFloatImplementation.mul(
                        signedCoefficientResult, exponentResult, signedCoefficientBase, exponentBase
                    );
                }
                exponentBInteger >>= 1;
                (signedCoefficientBase, exponentBase) = LibDecimalFloatImplementation.mul(
                    signedCoefficientBase, exponentBase, signedCoefficientBase, exponentBase
                );
                // Squaring doubles the exponent, so left unchecked it overflows
                // int256 and panics. A base this far out means the result,
                // which moves away from 1 with it, cannot be packed either.
                if (exponentBase > type(int128).max) {
                    revert ExponentOverflow(signedCoefficientBase, exponentBase);
                }
                if (exponentBase < type(int128).min) {
                    revert ExponentUnderflow(signedCoefficientBase, exponentBase);
                }
            }
        }

        if (fractionB != 0) {
            (int256 signedCoefficientC, int256 exponentC) =
                LibDecimalFloatImplementation.log10Unrounded(tablesDataContract, signedCoefficientA, exponentA);
            (signedCoefficientC, exponentC) =
                LibDecimalFloatImplementation.mul(signedCoefficientC, exponentC, fractionB, exponentB);
            (signedCoefficientC, exponentC) =
                LibDecimalFloatImplementation.pow10Unrounded(signedCoefficientC, exponentC);
            (signedCoefficientResult, exponentResult) = LibDecimalFloatImplementation.mul(
                signedCoefficientC, exponentC, signedCoefficientResult, exponentResult
            );
        }
        return (signedCoefficientResult, exponentResult);
    }

    /// Rounds to 41 significant digits and packs. A rounding that carries
    /// above the largest Float packs the unrounded value instead.
    function packRoundedSignificant(int256 signedCoefficient, int256 exponent) private pure returns (Float) {
        (int256 roundedCoefficient, int256 roundedExponent) =
            LibDecimalFloatImplementation.roundSignificant(signedCoefficient, exponent);
        // Only a carry can leave the unrounded value packable, so a value that
        // int224 could not hold either way reports the rounded value.
        int256 excess = roundedExponent - type(int32).max;
        if (excess > 0 && excess <= 67) {
            // excess is in [1, 67] so the casts cannot truncate.
            // forge-lint: disable-next-line(unsafe-typecast)
            int256 scale = int256(10 ** uint256(excess));
            if (roundedCoefficient > type(int224).max / scale || roundedCoefficient < type(int224).min / scale) {
                return packArithmeticResult(signedCoefficient, exponent);
            }
        }
        return packArithmeticResult(roundedCoefficient, roundedExponent);
    }

    function isOne(int256 signedCoefficient, int256 exponent) private pure returns (bool) {
        (int256 signedCoefficientOne, int256 exponentOne) = FLOAT_ONE.unpack();
        return LibDecimalFloatImplementation.eq(signedCoefficient, exponent, signedCoefficientOne, exponentOne);
    }

    function isBelowOne(int256 signedCoefficient, int256 exponent) private pure returns (bool) {
        (int256 signedCoefficientOne, int256 exponentOne) = FLOAT_ONE.unpack();
        return LibDecimalFloatImplementation.lt(signedCoefficient, exponent, signedCoefficientOne, exponentOne);
    }

    /// An integer part of b past int256 is over 5.7e76 and every a but 1 is at
    /// least 1e-67 from it, so |b log10(a)| is over 2.5e9: the power is past
    /// the range, on the side a is of 1.
    function revertIfIntegerBPastInt256(int256 signedCoefficientA, int256 exponentA, int256 integerB, int256 exponentB)
        private
        pure
    {
        // forge-lint: disable-next-line(unsafe-typecast)
        if (exponentB > 76 || (exponentB > 0 && integerB > type(int256).max / int256(10 ** uint256(exponentB)))) {
            if (isBelowOne(signedCoefficientA, exponentA)) {
                revert ExponentUnderflow(signedCoefficientA, exponentA);
            }
            revert ExponentOverflow(signedCoefficientA, exponentA);
        }
    }

    /// sqrt a = a ^ 0.5
    ///
    /// As `pow`: within 5.0000004e-41 relative of the true value, rounded to
    /// nearest at 41 significant digits. Monotone within rounding error: for
    /// x < y the roots can be out of order by exactly one unit in the last
    /// place, only when both true values lie within the raw error of the same
    /// rounding tie, and never by more. Callers must not rely on strict
    /// ordering at one-ulp resolution. A perfect square whose root has at most
    /// 41 significant digits has an exact root.
    ///
    /// Doesn't lose precision due to the exponent, for a wide range of
    /// exponents.
    /// @param a The float to take the square root of.
    /// @param tablesDataContract Unused, and kept so that callers need not
    /// change.
    /// @return The square root of a.
    function sqrt(Float a, address tablesDataContract) internal pure returns (Float) {
        return pow(a, FLOAT_HALF, tablesDataContract);
    }

    /// Returns the minimum of two values.
    /// Convenience for `a < b ? a : b`.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return The minimum of the two floats.
    function min(Float a, Float b) internal pure returns (Float) {
        return lt(a, b) ? a : b;
    }

    /// Returns the maximum of two values.
    /// Convenience for `a > b ? a : b`.
    /// @param a The first float to compare.
    /// @param b The second float to compare.
    /// @return The larger of the two floats.
    function max(Float a, Float b) internal pure returns (Float) {
        return gt(a, b) ? a : b;
    }

    /// Whether the two extremes of a set of values are close enough to each
    /// other, given an absolute and a proportional tolerance.
    ///
    /// `highest - lowest <= max(absolute, proportional * max(abs(lowest), abs(highest)))`
    ///
    /// BOTH TOLERANCES ARE TAKEN, and the LARGER of the two terms is the
    /// limit. A proportional tolerance alone collapses as the values approach
    /// zero, because the quantity it is a proportion of shrinks with them: a
    /// pair like `-0.001` and `0.001` reads as 200% apart while agreeing by
    /// any practical measure. An absolute tolerance alone does not scale. The
    /// absolute term therefore carries the region near zero and the
    /// proportional term carries the rest.
    ///
    /// The same form as `math.isclose` (PEP 485) and Julia's `isapprox`.
    /// `numpy.isclose` sums the two terms instead.
    ///
    /// THE PROPORTION IS OF THE LARGER MAGNITUDE of the two extremes. Every
    /// other value in a set lies between them, so no value in the set has a
    /// magnitude exceeding both, which makes this the largest magnitude in the
    /// whole set. Holding one anchor for the set is what makes a single
    /// highest-to-lowest check equivalent to checking every pair: the spread
    /// is the largest pairwise difference, so bounding it bounds all of them.
    ///
    /// NOTHING IS PACKED BACK INTO A `Float` before the comparison, which is
    /// the reason this cannot be composed from the public surface. That
    /// surface reverts `ExponentOverflow` rather than truncating an exponent,
    /// and both `abs` and `sub` do so on the extremes of the range: a set
    /// spanning the most negative to the most positive representable value has
    /// a spread that no packed value can hold. A closeness test asked about
    /// representable values should answer, not revert.
    ///
    /// THE COMPARISON IS EXACT ONLY TO REPRESENTABLE PRECISION. The spread is a
    /// subtraction, and a subtraction aligns exponents by discarding the
    /// smaller operand's low digits; past a gap of `ADD_MAX_EXPONENT_DIFF` the
    /// smaller operand is dropped whole. When those discarded digits would have
    /// carried the spread above the limit, and the spread as computed lands
    /// exactly on the limit, this returns true where an exact comparison would
    /// return false. `agree(0, 1, -1e-100, 1)` is such a case: the real spread
    /// is `1 + 1e-100`, needing 101 significant digits against the
    /// coefficient's 76, so `sub` returns exactly `1` and `1 <= 1` holds.
    ///
    /// That is the rounding every other operation here performs, and `sub`
    /// reports the same spread as exactly `1` when asked directly. Resolving
    /// the boundary the other way would put this function at odds with the
    /// library's own arithmetic. The excess it admits is bounded by one unit in
    /// the last place of the aligned coefficient, so a spread accepted at the
    /// boundary exceeds the limit by less than `1e-76` of its own magnitude.
    ///
    /// NEITHER TOLERANCE MAY BE NEGATIVE, and AT LEAST ONE MUST BE POSITIVE.
    /// Both are rejected here rather than given a meaning, and rejected here
    /// rather than left to callers, because a guard a caller can skip is not a
    /// guard. See `AgreeToleranceNegative` and `AgreeNoPositiveTolerance` for
    /// what each would otherwise silently do. Either tolerance ALONE may be
    /// zero, which is how a caller asks for only the other one.
    /// @param absolute The absolute tolerance, in the same units as the values.
    /// @param proportional The proportional tolerance, as a fraction.
    /// @param lowest The lowest value in the set.
    /// @param highest The highest value in the set.
    /// @return Whether the spread is within the limit.
    function agree(Float absolute, Float proportional, Float lowest, Float highest) internal pure returns (bool) {
        agreeValidateTolerances(absolute, proportional);
        (int256 spreadCoefficient, int256 spreadExponent) = agreeSpread(lowest, highest);
        (int256 limitCoefficient, int256 limitExponent) = agreeLimit(absolute, proportional, lowest, highest);
        return LibDecimalFloatImplementation.lte(spreadCoefficient, spreadExponent, limitCoefficient, limitExponent);
    }

    /// Rejects tolerances that do not describe a tolerance.
    ///
    /// A NEGATIVE tolerance cannot mean anything. The spread is a distance, so
    /// it is non-negative, which makes `spread <= negative` unsatisfiable on its
    /// own and makes the negative term inert under the `max` — it cannot cancel
    /// the other term, only fail to be it. It is representable solely because
    /// floats are signed.
    ///
    /// NEITHER POSITIVE is a tolerance of nothing: the limit is zero and this
    /// degenerates into exact equality, which `eq` answers directly. A caller
    /// reaching for a closeness test and getting exact equality has been
    /// misunderstood rather than served.
    ///
    /// Rejected here rather than in each caller, because a guard a caller can
    /// skip is not a guard.
    ///
    /// Both tests compare against a zero `Float` rather than unpacking, so every
    /// representation of zero is treated alike. The positive test is stated as
    /// `neither is greater than zero` rather than `both are zero`, so it names
    /// the invariant rather than one case that violates it, and stays correct if
    /// the negative check is ever changed.
    /// @param absolute The absolute tolerance.
    /// @param proportional The proportional tolerance.
    function agreeValidateTolerances(Float absolute, Float proportional) private pure {
        Float zero = packLossless(0, 0);
        if (lt(absolute, zero) || lt(proportional, zero)) {
            revert AgreeToleranceNegative(absolute, proportional);
        }
        if (!gt(absolute, zero) && !gt(proportional, zero)) {
            revert AgreeNoPositiveTolerance(absolute, proportional);
        }
    }

    /// The distance between the two extremes, unpacked.
    ///
    /// Split out of `agree` because holding the four unpacked values and the
    /// intermediates in one frame exceeds the stack.
    /// @param lowest The lowest value.
    /// @param highest The highest value.
    /// @return The spread's coefficient.
    /// @return The spread's exponent.
    function agreeSpread(Float lowest, Float highest) private pure returns (int256, int256) {
        (int256 lowestCoefficient, int256 lowestExponent) = lowest.unpack();
        (int256 highestCoefficient, int256 highestExponent) = highest.unpack();
        // Destructured rather than returned directly because slither reads
        // `return f(...)` on a tuple-returning call as an ignored return.
        (int256 spreadCoefficient, int256 spreadExponent) =
            LibDecimalFloatImplementation.sub(highestCoefficient, highestExponent, lowestCoefficient, lowestExponent);
        return (spreadCoefficient, spreadExponent);
    }

    /// The quantity the proportional tolerance is taken of: the larger
    /// magnitude of the two extremes.
    /// @param lowest The lowest value.
    /// @param highest The highest value.
    /// @return The anchor's coefficient, non-negative.
    /// @return The anchor's exponent.
    function agreeAnchor(Float lowest, Float highest) private pure returns (int256, int256) {
        (int256 lowestCoefficient, int256 lowestExponent) = lowest.unpack();
        (int256 highestCoefficient, int256 highestExponent) = highest.unpack();
        (int256 anchorCoefficient, int256 anchorExponent) = LibDecimalFloatImplementation.max(
            LibDecimalFloatImplementation.absCoefficient(lowestCoefficient),
            lowestExponent,
            LibDecimalFloatImplementation.absCoefficient(highestCoefficient),
            highestExponent
        );
        return (anchorCoefficient, anchorExponent);
    }

    /// The limit the spread is checked against: the larger of the absolute
    /// tolerance and the proportional tolerance of the anchor.
    /// @param absolute The absolute tolerance.
    /// @param proportional The proportional tolerance.
    /// @param lowest The lowest value.
    /// @param highest The highest value.
    /// @return The limit's coefficient.
    /// @return The limit's exponent.
    function agreeLimit(Float absolute, Float proportional, Float lowest, Float highest)
        private
        pure
        returns (int256, int256)
    {
        int256 scaledCoefficient;
        int256 scaledExponent;
        {
            (int256 anchorCoefficient, int256 anchorExponent) = agreeAnchor(lowest, highest);
            (int256 proportionalCoefficient, int256 proportionalExponent) = proportional.unpack();
            (scaledCoefficient, scaledExponent) = LibDecimalFloatImplementation.mul(
                proportionalCoefficient, proportionalExponent, anchorCoefficient, anchorExponent
            );
        }
        (int256 absoluteCoefficient, int256 absoluteExponent) = absolute.unpack();
        (int256 limitCoefficient, int256 limitExponent) =
            LibDecimalFloatImplementation.max(absoluteCoefficient, absoluteExponent, scaledCoefficient, scaledExponent);
        return (limitCoefficient, limitExponent);
    }

    /// Returns true if the float is zero. Handles the case where the signed
    /// coefficient is zero and exponent is potentially non zero.
    /// @param a The float to check.
    /// @return result True if the float is zero.
    function isZero(Float a) internal pure returns (bool result) {
        uint256 mask = type(uint224).max;
        assembly ("memory-safe") {
            // Don't need to signextend here because we only care if the value
            // is zero or not.
            result := iszero(and(a, mask))
        }
    }

    /// Returns true if the float is an odd whole number. A float that is not
    /// whole is not odd. Exact: no float division or modulo is involved.
    /// @param a The float to check.
    /// @return True if the float is an odd whole number.
    function isOdd(Float a) internal pure returns (bool) {
        (int256 signedCoefficient, int256 exponent) = a.unpack();
        if (exponent > 0) {
            // A whole multiple of ten.
            return false;
        }
        if (exponent < -67) {
            // An int224 coefficient has at most 68 digits, so the value is
            // either zero or strictly between -1 and 1.
            return false;
        }
        // exponent is in [-67, 0] so the power fits int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 scale = int256(10 ** uint256(-exponent));
        return signedCoefficient % scale == 0 && (signedCoefficient / scale) & 1 == 1;
    }
}
