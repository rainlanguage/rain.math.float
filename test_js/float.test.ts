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
	}
});
