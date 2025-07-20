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

		it('should test format18 and fromFixedDecimal', () => {
			const float = Float.fromFixedDecimal(12345n, 2)?.value!;
			expect(float.format18()?.value!).toBe('123.45');
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

		it('should test packLossless', () => {
			const float = Float.packLossless('314', -2)?.value!;
			expect(float.format()?.value!).toBe('3.14');
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
	}
});
