import { Float } from '../dist/cjs';
import { describe, it, expect, assert } from 'vitest';

describe('Test Float Bindings', async function () {
	it('should try from bigint', async function () {
		const result = Float.tryFromBigint(5n);
		assert.ok(result.error === undefined, `Expected no error, but got: ${result.error?.readableMsg}`);

		const expected = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000000005')?.value!;
		expect(result.value.eq(expected)).toBeTruthy();
	});

	it('should convert from bigint', async function () {
		const result = Float.fromBigint(18n);
		const expected = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000000012')?.value!;
		expect(result.eq(expected)).toBeTruthy();
	});

	it('should try to bigint', async function () {
		const float = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000000008')?.value!;
		const result = float.tryToBigint();
		assert.ok(result.error === undefined, `Expected no error, but got: ${result.error?.readableMsg}`);

		expect(result.value).toBe(8n);
	});

	it('should convert to bigint', async function () {
		const float = Float.fromHex('0x0000000000000000000000000000000000000000000000000000000000001234')?.value!;
		const result = float.toBigint();

		expect(result).toBe(BigInt('0x1234'));
	});

	it('should test logic ops', async function () {
		const a = Float.fromBigint(1n);
		const b = Float.fromBigint(2n);
		const c = Float.fromBigint(1n);
		const zero = Float.fromBigint(0n);

		expect(a.lt(b)).toBeTruthy();
		expect(a.lte(b)).toBeTruthy();
		expect(a.lte(c)).toBeTruthy();

		expect(b.gt(a)).toBeTruthy();
		expect(b.gte(a)).toBeTruthy();
		expect(c.gte(a)).toBeTruthy();

		expect(a.eq(c)).toBeTruthy();
		expect(zero.isZero()).toBeTruthy();

		expect(a.max(b)?.value!.eq(b)).toBeTruthy();
		expect(a.min(b)?.value!.eq(a)).toBeTruthy();
	});

	it('should test math ops', async function () {
		const a = Float.parse("3.14")?.value!;
		const b = Float.parse("-3.14")?.value!;
		const c = Float.parse("2.0")?.value!;

		expect(a.floor()?.value!.format()?.value!).toBe("3");
		expect(a.frac()?.value!.format()?.value!).toBe("0.14");
		expect(c.inv()?.value!.format()?.value!).toBe("0.5");
		expect(b.abs()?.value!.format()?.value!).toBe("3.14");
		expect(a.sub(b)?.value!.format()?.value!).toBe("6.28");
		expect(a.mul(c)?.value!.format()?.value!).toBe("6.28");
		expect(a.div(c)?.value!.format()?.value!).toBe("1.57");
		expect(a.div(b)?.value!.format()?.value!).toBe("-1");
		expect(a.add(b)?.value!.format()?.value!).toBe("0");
	});
});
