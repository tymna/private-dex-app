// 256-bit math helpers for the AMM contract.
//
// Native u128 overflows on `a * b` once operands exceed ~1.84e19. AMM math
// (`amount * supply / reserve`) needs 256-bit headroom for the intermediate
// product. We represent a u256 as (lo: u128, hi: u128) and provide:
//   - carry-safe multiplication and addition for in-circuit verification,
//   - an unconstrained binary long-division for the hint.
//
// mul_u128_to_u256 and add_u256_u128 are adapted from the reference
// "High-Precision 256-Bit Integer Arithmetic in Noir and Aztec Smart
// Contracts" (Downloads/Noir 256-bit Arithmetic for Aztec.md).
// divmod_u256_u128 is our own (the reference used noir-bignum here).

// ----- mul_u128_to_u256 ----- //
// ---------------------------- //
// Splits each u128 into two u64 halves. u64*u64 < 2^128, so no
// intermediate overflows. Combines the four partials with explicit carries.
// Result: a*b == hi * 2^128 + lo.
// Source: reference doc, "Carry-safe 128-bit by 128-bit multiplication".
pub fn mul_u128_to_u256(a: u128, b: u128) -> (u128, u128) {
    let a0 = a as u64 as u128;
    let a1 = a >> 64;
    let b0 = b as u64 as u128;
    let b1 = b >> 64;

    let w0 = a0 * b0;
    let p1 = a0 * b1;
    let p2 = a1 * b0;
    let w2 = a1 * b1;

    let w0_lo = w0 as u64 as u128;
    let w0_hi = w0 >> 64;

    let p1_lo = p1 as u64 as u128;
    let p1_hi = p1 >> 64;
    let p2_lo = p2 as u64 as u128;
    let p2_hi = p2 >> 64;

    let sum_lo = p1_lo + p2_lo + w0_hi;
    let w1_lo = sum_lo as u64 as u128;
    let carry = sum_lo >> 64;

    let w1_hi = p1_hi + p2_hi + carry;

    let lo = w0_lo | (w1_lo << 64);
    let hi = w2 + w1_hi;

    (lo, hi)
}

// ----- add_u256_u128 ----- //
// ------------------------- //
// Carry-safe addition of u128 y into u256 (x_lo, x_hi).
// Done via u64-half addition to avoid native u128 overflow.
// Assumes the u256 result fits (true for mul_div use).
// Source: reference doc, "Carry-safe addition of a 256-bit integer and a 128-bit integer".
pub fn add_u256_u128(x_lo: u128, x_hi: u128, y: u128) -> (u128, u128) {
    let x0 = x_lo as u64 as u128;
    let x1 = x_lo >> 64;
    let y0 = y as u64 as u128;
    let y1 = y >> 64;

    let sum0 = x0 + y0;
    let carry1 = sum0 >> 64;
    let z0 = sum0 as u64 as u128;

    let sum1 = x1 + y1 + carry1;
    let carry2 = sum1 >> 64;
    let z1 = sum1 as u64 as u128;

    let new_lo = z0 | (z1 << 64);
    let new_hi = x_hi + carry2;

    (new_lo, new_hi)
}

// ----- divmod_u256_u128 ----- //
// ---------------------------- //
// Binary long-division: (num_lo, num_hi) / divisor -> (q, r).
// Iterates 256 bits high-to-low. Each step shifts a bit of the numerator
// into the running remainder; if r >= divisor, subtract and set the
// quotient bit. Unconstrained: only called from mul_div_hint.
// Source: original.
pub unconstrained fn divmod_u256_u128(num_lo: u128, num_hi: u128, divisor: u128) -> (u128, u128) {
    let mut q_lo: u128 = 0;
    let mut q_hi: u128 = 0;
    let mut r: u128 = 0;

    for i in 0..128 {
        let bit_pos = 127 - i;
        let bit = (num_hi >> bit_pos) & 1;
        r = (r << 1) | bit;
        if r >= divisor {
            r = r - divisor;
            q_hi = q_hi | (1 << bit_pos);
        }
    }

    for i in 0..128 {
        let bit_pos = 127 - i;
        let bit = (num_lo >> bit_pos) & 1;
        r = (r << 1) | bit;
        if r >= divisor {
            r = r - divisor;
            q_lo = q_lo | (1 << bit_pos);
        }
    }

    // For mul_div use we expect q_hi == 0. If it isn't, the verifier in
    // mul_div will fail the invariant and the tx reverts.
    (q_lo, r)
}

// ----- get_amount_out ----- //
// -------------------------- //
// CPMM output for a swap: floor( amount_in*(D-fee) * reserve_out / (reserve_in*D + amount_in*(D-fee)) ).
// fee_rate is in parts-per-10000. mul_div carries the only product that exceeds u128.
pub fn get_amount_out(amount_in: u128, reserve_in: u128, reserve_out: u128, fee_rate: u32) -> u128 {
    let amount_in_with_fee = amount_in * (10000 - fee_rate as u128);
    let denominator = reserve_in * 10000 + amount_in_with_fee;
    mul_div(amount_in_with_fee, reserve_out, denominator)
}

// ----- mul_div ----- //
// ------------------- //
// Returns floor(a * b / c) as u128 without overflowing.
// Hint-and-verify:
//   1. Untrusted hint gives (q, r).
//   2. Verify a*b == q*c + r (in 256-bit) and r < c.
//   3. Return q. Asserts pin it to exactly floor(a*b/c).
// Domain: c must be <= 2^127. For larger divisors divmod's running-remainder shift (`r << 1`)
// overflows u128 and the hint returns garbage; the verify below then reverts. That's safe (never
// a wrong answer) but unsupported - and 2^127 (~1.7e38) is far above any real token amount.
// Source: adapted from reference doc's "safe_mul_div" (the doc's version uses
// noir-bignum for the hint; ours uses divmod_u256_u128 above).
pub fn mul_div(a: u128, b: u128, c: u128) -> u128 {
    assert(c != 0 as u128, "mul_div by zero");

    // SAFETY: (q, r) are untrusted; the asserts below pin them down.
    let (q, r) = unsafe { mul_div_hint(a, b, c) };

    let (num_lo, num_hi) = mul_u128_to_u256(a, b);
    let (qc_lo, qc_hi) = mul_u128_to_u256(q, c);
    let (rec_lo, rec_hi) = add_u256_u128(qc_lo, qc_hi, r);

    assert(num_lo == rec_lo, "mul_div invariant (lo)");
    assert(num_hi == rec_hi, "mul_div invariant (hi)");
    assert(r < c, "remainder out of range");

    q
}

// ----- mul_div_hint ----- //
// ------------------------ //
// Produces (q, r) such that a*b == q*c + r with r < c.
// Untrusted: only called from mul_div, which verifies in-circuit.
// Source: original (glue around mul_u128_to_u256 + divmod_u256_u128).
pub unconstrained fn mul_div_hint(a: u128, b: u128, c: u128) -> (u128, u128) {
    let (lo, hi) = mul_u128_to_u256(a, b);
    divmod_u256_u128(lo, hi, c)
}

// ----- isqrt_u256 ----- //
// ---------------------- //
// Floor sqrt of a u256 (num_lo, num_hi) returned as u128.
// Hint-and-verify:
//   1. Hint gives s.
//   2. Assert s*s <= num.
//   3. Assert (s+1)*(s+1) > num.
// Sources:
//   - Aztec docs "Writing Efficient Contracts" recommend hint+verify for sqrt
//     (perfect-square example: `assert(x*x == n)`).
//   - The two-sided invariant `s*s <= num < (s+1)*(s+1)` is the standard
//     math definition of floor sqrt (not Aztec-specific).
pub fn isqrt_u256(num_lo: u128, num_hi: u128) -> u128 {
    // SAFETY: untrusted hint, pinned down by the asserts below.
    let s = unsafe { isqrt_u256_hint(num_lo, num_hi) };

    // s*s <= num
    let (s2_lo, s2_hi) = mul_u128_to_u256(s, s);
    let s2_le_num = (s2_hi < num_hi) | ((s2_hi == num_hi) & (s2_lo <= num_lo));
    assert(s2_le_num, "isqrt: s*s > num");

    // (s+1)*(s+1) > num
    // Realistic AMM inputs are far from u128::MAX, so s+1 won't overflow.
    // If a caller did push s to u128::MAX, s+1 would panic and the tx reverts,
    // which is safe (just not graceful).
    let s_plus_1 = s + 1;
    let (sp_lo, sp_hi) = mul_u128_to_u256(s_plus_1, s_plus_1);
    let sp_gt_num = (sp_hi > num_hi) | ((sp_hi == num_hi) & (sp_lo > num_lo));
    assert(sp_gt_num, "isqrt: (s+1)^2 <= num");

    s
}

// ----- isqrt_u256_hint ----- //
// --------------------------- //
// Unconstrained floor sqrt via bit-by-bit search.
// Tries each bit from highest to lowest; sets the bit if doing so keeps
// s*s <= num. 128 iterations, one u128*u128 mul each.
// Source: classic digit-by-digit integer sqrt algorithm (general CS, not
// Aztec-specific).
pub unconstrained fn isqrt_u256_hint(num_lo: u128, num_hi: u128) -> u128 {
    let mut result: u128 = 0;

    for i in 0..128 {
        let bit_pos = 127 - i;
        let candidate = result | ((1 as u128) << bit_pos);
        let (c2_lo, c2_hi) = mul_u128_to_u256(candidate, candidate);
        let c2_le_num = (c2_hi < num_hi) | ((c2_hi == num_hi) & (c2_lo <= num_lo));
        if c2_le_num {
            result = candidate;
        }
    }

    result
}
