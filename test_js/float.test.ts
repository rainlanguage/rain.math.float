import { describe, it, expect, assert } from 'vitest';

describe('Test Float Bindings', () => {
	describe('CJS', async () => {
		await runTests('cjs');
	});

	describe('ESM', async () => {
		await runTests('esm');
	});

	async function runTests(mod: 'cjs' | 'esm') {
		// load the Float class from the appropriate module
		const { Float } = await (mod === 'cjs' ? import('../dist/cjs') : import('../dist/esm'));

		it('should test parse', () => {
			const float = Float.parse('3.14')?.value!;
			expect(float.asHex()).toBe('0xfffffffe0000000000000000000000000000000000000000000000000000013a');
		});

		it('should test format', () => {
			const float = Float.fromHex('0xfffffffe0000000000000000000000000000000000000000000000000000013a')?.value!;
			expect(float.format()?.value!).toBe('3.14');
		});

		it('should test format and fromFixedDecimal', () => {
			const float = Float.fromFixedDecimal(12345n, 2)?.value!;
			expect(float.format()?.value!).toBe('123.45');
		});

		it('should test toFixedDecimal', () => {
			const float = Float.parse('123.45')?.value!;
			expect(float.toFixedDecimal(2)?.value!).toBe(12345n);
		});

		it('should test toFixedDecimal roundtrip', () => {
			const originalValue = 9876543210n;
			const decimals = 8;
			const float = Float.fromFixedDecimal(originalValue, decimals)?.value!;
			const result = float.toFixedDecimal(decimals)?.value!;
			expect(result).toBe(originalValue);
		});

		it('should test fromFixedDecimalLossy with lossless conversion', () => {
			const result = Float.fromFixedDecimalLossy(12345n, 2);
			expect(result.float.format()?.value!).toBe('123.45');
			expect(result.lossless).toBe(true);
		});

		it('should test toFixedDecimalLossy with lossy conversion', () => {
			const float = Float.fromFixedDecimal(12345n, 3)?.value!;
			const result = float.toFixedDecimalLossy(2);
			expect(result.error).toBeUndefined();
			expect(result.value!.value).toBe('1234');
			expect(result.value!.lossless).toBe(false);
		});

		it('should test toFixedDecimalLossy with lossless conversion', () => {
			const float = Float.fromFixedDecimal(12340n, 3)?.value!;
			const result = float.toFixedDecimalLossy(2);
			expect(result.error).toBeUndefined();
			expect(result.value!.value).toBe('1234');
			expect(result.value!.lossless).toBe(true);
		});


		it('should try from bigint', () => {
			const result = Float.tryFromBigint(5n);
			assert.ok(result.error === undefined, `Expected no error, but got: ${result.error?.readableMsg}`);

			const expected = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000000005')?.value!;
			expect(result.value.eq(expected)).toBeTruthy();
		});

		it('should convert from bigint', () => {
			const result = Float.fromBigint(18n);
			const expected = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000000012')?.value!;
			expect(result.eq(expected)).toBeTruthy();
		});

		it('should try to bigint', () => {
			const float = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000000008')?.value!;
			const result = float.tryToBigint();
			assert.ok(result.error === undefined, `Expected no error, but got: ${result.error?.readableMsg}`);

			expect(result.value).toBe(8n);
		});

		it('should convert to bigint', () => {
			const float = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000001234')?.value!;
			const result = float.toBigint();

			expect(result).toBe(BigInt('0x1234'));
		});

		it('should test logic ops', () => {
			const a = Float.fromBigint(1n);
			const b = Float.fromBigint(2n);
			const c = Float.fromBigint(1n);
			const zero = Float.fromBigint(0n);
			const neg = Float.parse('-1')?.value!;

			expect(a.lt(b)?.value!).toBe(true);
			expect(a.lte(b)?.value!).toBe(true);
			expect(a.lte(c)?.value!).toBe(true);

			expect(b.gt(a)?.value!).toBe(true);
			expect(b.gte(a)?.value!).toBe(true);
			expect(c.gte(a)?.value!).toBe(true);

			expect(a.eq(c)?.value!).toBe(true);
			expect(zero.isZero()?.value!).toBe(true);
			expect(neg.neg()?.value!.eq(a)?.value!).toBe(true);

			expect(a.max(b)?.value!.eq(b)?.value!).toBe(true);
			expect(a.min(b)?.value!.eq(a)?.value!).toBe(true);
		});

		it('should test math ops', () => {
			const a = Float.parse('3.14')?.value!;
			const b = Float.parse('-3.14')?.value!;
			const c = Float.parse('2.0')?.value!;

			expect(a.floor()?.value!.format()?.value!).toBe('3');
			expect(a.frac()?.value!.format()?.value!).toBe('0.14');
			expect(c.inv()?.value!.format()?.value!).toBe('0.5');
			expect(b.abs()?.value!.format()?.value!).toBe('3.14');
			expect(a.sub(b)?.value!.format()?.value!).toBe('6.28');
			expect(a.mul(c)?.value!.format()?.value!).toBe('6.28');
			expect(a.div(c)?.value!.format()?.value!).toBe('1.57');
			expect(a.div(b)?.value!.format()?.value!).toBe('-1');
			expect(a.add(b)?.value!.format()?.value!).toBe('0');
		});

		it('should test zero constant', () => {
			// Test the zero function
			const zeroResult = Float.zero();
			expect(zeroResult.error).toBeUndefined();

			const zero = zeroResult.value!;

			// Test that zero is actually zero
			expect(zero.isZero()?.value!).toBe(true);
			expect(zero.format()?.value!).toBe('0');

			// Test that zero equals parsed zero
			const parsedZero = Float.parse('0')?.value!;
			expect(zero.eq(parsedZero)?.value!).toBe(true);

			// Test that zero equals bigint zero
			const bigintZero = Float.fromBigint(0n);
			expect(zero.eq(bigintZero)?.value!).toBe(true);
		});

		it('should test float constants', () => {
			// Test that all constant methods return valid floats
			const maxPosResult = Float.maxPositiveValue();
			const minPosResult = Float.minPositiveValue();
			const maxNegResult = Float.maxNegativeValue();
			const minNegResult = Float.minNegativeValue();

			// Verify no errors occurred
			expect(maxPosResult.error).toBeUndefined();
			expect(minPosResult.error).toBeUndefined();
			expect(maxNegResult.error).toBeUndefined();
			expect(minNegResult.error).toBeUndefined();

			const maxPos = maxPosResult.value!;
			const minPos = minPosResult.value!;
			const maxNeg = maxNegResult.value!;
			const minNeg = minNegResult.value!;

			const zero = Float.fromBigint(0n);
			const one = Float.parse('1')?.value!;
			const negOne = Float.parse('-1')?.value!;

			// Test mathematical properties without exposing binary representation

			// All constants should be distinct
			expect(maxPos.eq(minPos)?.value!).toBe(false);
			expect(maxNeg.eq(minNeg)?.value!).toBe(false);
			expect(maxPos.eq(maxNeg)?.value!).toBe(false);
			expect(minPos.eq(minNeg)?.value!).toBe(false);

			// Test sign properties
			expect(minPos.gt(zero)?.value!).toBe(true); // min positive > 0
			expect(maxPos.gt(zero)?.value!).toBe(true); // max positive > 0
			expect(maxNeg.lt(zero)?.value!).toBe(true); // max negative < 0
			expect(minNeg.lt(zero)?.value!).toBe(true); // min negative < 0

			// Test ordering relationships
			expect(minPos.lt(maxPos)?.value!).toBe(true); // min positive < max positive
			expect(minNeg.lt(maxNeg)?.value!).toBe(true); // min negative < max negative

			// Test boundary properties
			expect(maxPos.gt(one)?.value!).toBe(true); // max positive > 1
			expect(minPos.lt(one)?.value!).toBe(true); // min positive < 1
			expect(maxNeg.gt(negOne)?.value!).toBe(true); // max negative > -1
			expect(minNeg.lt(negOne)?.value!).toBe(true); // min negative < -1
		});

		it('should test format default scientific notation constants', () => {
			const minResult = Float.formatDefaultScientificMin();
			const maxResult = Float.formatDefaultScientificMax();

			expect(minResult.error).toBeUndefined();
			expect(maxResult.error).toBeUndefined();

			const min = minResult.value!;
			const max = maxResult.value!;

			// Verify the values
			expect(min.format()?.value!).toBe('0.0001'); // 1e-4
			expect(max.format()?.value!).toBe('1000000000'); // 1e9
		});

		it('should test default formatting behavior', () => {
			// Values within default range (1e-4 to 1e9) should use decimal notation
			const small = Float.parse('0.0001')?.value!;
			expect(small.format()?.value!).toBe('0.0001');

			const normal = Float.parse('123.456')?.value!;
			expect(normal.format()?.value!).toBe('123.456');

			const large = Float.parse('1000000000')?.value!;
			expect(large.format()?.value!).toBe('1000000000');

			// Values outside default range should use scientific notation
			const tooSmall = Float.parse('0.00001')?.value!;
			expect(tooSmall.format()?.value!).toBe('1e-5');

			const tooLarge = Float.parse('10000000000')?.value!;
			expect(tooLarge.format()?.value!).toBe('1e10');
		});

		it('should test formatWithScientific boolean control', () => {
			const float = Float.parse('123.456')?.value!;

			// Explicit decimal notation
			const decimal = float.formatWithScientific(false);
			expect(decimal.error).toBeUndefined();
			expect(decimal.value!).toBe('123.456');

			// Explicit scientific notation
			const scientific = float.formatWithScientific(true);
			expect(scientific.error).toBeUndefined();
			expect(scientific.value!).toBe('1.23456e2');

			// Test with very small number
			const small = Float.parse('0.00001')?.value!;
			const smallDecimal = small.formatWithScientific(false);
			expect(smallDecimal.value!).toBe('0.00001');

			const smallScientific = small.formatWithScientific(true);
			expect(smallScientific.value!).toBe('1e-5');
		});

		it('should test formatWithRange custom ranges', () => {
			const float = Float.parse('0.5')?.value!;
			const min = Float.parse('1')?.value!;
			const max = Float.parse('100')?.value!;

			// 0.5 is smaller than min (1), so should use scientific notation
			const result = float.formatWithRange(min, max);
			expect(result.error).toBeUndefined();
			expect(result.value!).toBe('5e-1');

			// Value within custom range
			const inRange = Float.parse('50')?.value!;
			const inRangeResult = inRange.formatWithRange(min, max);
			expect(inRangeResult.value!).toBe('50');

			// Value outside custom range (too large)
			const outOfRange = Float.parse('1000')?.value!;
			const outOfRangeResult = outOfRange.formatWithRange(min, max);
			expect(outOfRangeResult.value!).toBe('1e3');
		});

		it('should test formatting round-trip with new methods', () => {
			const original = Float.parse('0.0001')?.value!;

			// Format and parse back
			const formatted = original.format()?.value!;
			const parsed = Float.parse(formatted)?.value!;

			expect(original.eq(parsed)?.value!).toBe(true);

			// Test with scientific notation
			const scientific = original.formatWithScientific(true)?.value!;
			const parsedSci = Float.parse(scientific)?.value!;

			expect(original.eq(parsedSci)?.value!).toBe(true);
		});
	}
});
