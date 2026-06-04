// Unit tests for the 256-bit math helpers (crate::math).
//
// These are pure functions, so no TXE / TestEnvironment is needed - plain `#[test]`.
// Expected values are computed by hand (commented per case), NOT by re-running the
// implementation, so a carry/floor bug surfaces as a mismatch rather than hiding.
//
// Priority is on `mul_u128_to_u256` and `add_u256_u128`: they run *inside* the
// in-circuit verification of `mul_div`, so a bug there is silently wrong (the verified
// functions only ever revert on a bad hint, they can't return a wrong answer).
use crate::math::{add_u256_u128, get_amount_out, isqrt_u256, mul_div, mul_u128_to_u256};

global U128_MAX: u128 = 0xffffffffffffffffffffffffffffffff; // 2^128 - 1

// ----- mul_u128_to_u256 ----- //
// ---------------------------- //

// small product stays in the low word
#[test]
fn test_mul_u128_to_u256_small() {
    let (lo, hi) = mul_u128_to_u256(2, 3);
    assert(lo == 6, "lo == 6");
    assert(hi == 0, "hi == 0");
}

// exact 2^128 boundary: 2^64 * 2^64 == 2^128 == (lo = 0, hi = 1)
#[test]
fn test_mul_u128_to_u256_boundary_2_pow_128() {
    let (lo, hi) = mul_u128_to_u256((1 as u128) << 64, (1 as u128) << 64);
    assert(lo == 0, "lo == 0");
    assert(hi == 1, "hi == 1");
}

// carry across the 64-bit halves: (2^64 + 1)^2 == 2^128 + 2^65 + 1 == (lo = 2^65 + 1, hi = 1)
#[test]
fn test_mul_u128_to_u256_cross_half_carry() {
    let a = ((1 as u128) << 64) + 1;
    let (lo, hi) = mul_u128_to_u256(a, a);
    assert(lo == ((1 as u128) << 65) + 1, "lo == 2^65 + 1");
    assert(hi == 1, "hi == 1");
}

// ceiling: (2^128 - 1)^2 == 2^256 - 2^129 + 1 == (lo = 1, hi = 2^128 - 2)
#[test]
fn test_mul_u128_to_u256_max() {
    let (lo, hi) = mul_u128_to_u256(U128_MAX, U128_MAX);
    assert(lo == 1, "lo == 1");
    assert(hi == U128_MAX - 1, "hi == 2^128 - 2");
}

// ----- add_u256_u128 ----- //
// ------------------------- //

// no carry
#[test]
fn test_add_u256_u128_no_carry() {
    let (lo, hi) = add_u256_u128(5, 0, 3);
    assert(lo == 8, "lo == 8");
    assert(hi == 0, "hi == 0");
}

// carry from the low word into the high word: (2^128 - 1) + 1 == 2^128 == (lo = 0, hi = 1)
#[test]
fn test_add_u256_u128_carry_into_hi() {
    let (lo, hi) = add_u256_u128(U128_MAX, 0, 1);
    assert(lo == 0, "lo == 0");
    assert(hi == 1, "hi == 1");
}

// carry lands on top of an existing high word
#[test]
fn test_add_u256_u128_carry_onto_existing_hi() {
    let (lo, hi) = add_u256_u128(U128_MAX, 5, 1);
    assert(lo == 0, "lo == 0");
    assert(hi == 6, "hi == 5 + carry");
}

// MAX + MAX in the low word: 2*(2^128 - 1) == (lo = 2^128 - 2, hi = 1)
#[test]
fn test_add_u256_u128_max_plus_max() {
    let (lo, hi) = add_u256_u128(U128_MAX, 0, U128_MAX);
    assert(lo == U128_MAX - 1, "lo == 2^128 - 2");
    assert(hi == 1, "hi == 1");
}

// ----- mul_div ----- //
// ------------------- //

// exact division
#[test]
fn test_mul_div_exact() {
    assert(mul_div(10, 20, 4) == 50, "10*20/4 == 50");
}

// floor on a remainder: 30/4 == 7.5 -> 7
#[test]
fn test_mul_div_floors() {
    assert(mul_div(10, 3, 4) == 7, "floor(30/4) == 7");
}

// b == c -> result == a (sanity identity)
#[test]
fn test_mul_div_b_equals_c() {
    assert(mul_div(12345, 7, 7) == 12345, "a*c/c == a");
}

// 256-bit path: a*b overflows u128 (3.6e40), result fits. 100e18 * 360e18 / 240e18 == 150e18 exact
#[test]
fn test_mul_div_overflow_path_exact() {
    let r = mul_div(
        100_000_000_000_000_000_000,
        360_000_000_000_000_000_000,
        240_000_000_000_000_000_000,
    );
    assert(r == 150_000_000_000_000_000_000, "== 150e18");
}

// 256-bit path with floor: 100e18 * 160e18 / 240e18 == 66.666...e18 -> floored
#[test]
fn test_mul_div_overflow_path_floors() {
    let r = mul_div(
        100_000_000_000_000_000_000,
        160_000_000_000_000_000_000,
        240_000_000_000_000_000_000,
    );
    assert(r == 66_666_666_666_666_666_666, "floored 66.666...e18");
}

// largest realistic 256-bit path: 1e30 * 1e30 / 1e30 == 1e30. numerator (1e60) needs the
// 256-bit path; divisor is well under 2^127 so the hint's remainder shift never overflows.
// (a divisor > 2^127 overflows divmod's `r << 1`; mul_div's verify catches it and reverts,
// so it's safe but unsupported - and far above any real token amount.)
#[test]
fn test_mul_div_large_in_domain() {
    let big: u128 = 1_000_000_000_000_000_000_000_000_000_000; // 1e30
    assert(mul_div(big, big, big) == big, "1e30*1e30/1e30 == 1e30");
}

// division by zero is rejected
#[test(should_fail_with = "mul_div by zero")]
fn test_mul_div_by_zero_reverts() {
    let _ = mul_div(1, 1, 0);
}

// ----- isqrt_u256 ----- //
// ---------------------- //

// small exact and floor cases
#[test]
fn test_isqrt_zero() {
    assert(isqrt_u256(0, 0) == 0, "isqrt(0) == 0");
}

#[test]
fn test_isqrt_one() {
    assert(isqrt_u256(1, 0) == 1, "isqrt(1) == 1");
}

// non-square floors down: isqrt(2) == 1, isqrt(3) == 1, isqrt(15) == 3
#[test]
fn test_isqrt_floors() {
    assert(isqrt_u256(2, 0) == 1, "isqrt(2) == 1");
    assert(isqrt_u256(3, 0) == 1, "isqrt(3) == 1");
    assert(isqrt_u256(15, 0) == 3, "isqrt(15) == 3");
}

// perfect squares
#[test]
fn test_isqrt_perfect_squares() {
    assert(isqrt_u256(4, 0) == 2, "isqrt(4) == 2");
    assert(isqrt_u256(144, 0) == 12, "isqrt(144) == 12");
}

// large value exercising the high word: 2^200 == (lo = 0, hi = 2^72), sqrt == 2^100
#[test]
fn test_isqrt_large_hi_word() {
    let s = isqrt_u256(0, (1 as u128) << 72);
    assert(s == (1 as u128) << 100, "isqrt(2^200) == 2^100");
}

// the AMM initial-deposit shape: sqrt(360e18 * 160e18) == sqrt(57600e36) == 240e18 exactly
#[test]
fn test_isqrt_amm_seed_exact() {
    let (lo, hi) =
        mul_u128_to_u256(360_000_000_000_000_000_000, 160_000_000_000_000_000_000);
    assert(isqrt_u256(lo, hi) == 240_000_000_000_000_000_000, "isqrt == 240e18");
}

// floor boundary: one below a perfect square rounds down to s - 1.
// (240e18)^2 - 1 -> 240e18 - 1
#[test]
fn test_isqrt_one_below_perfect_square() {
    let (lo, hi) =
        mul_u128_to_u256(240_000_000_000_000_000_000, 240_000_000_000_000_000_000);
    // lo is nonzero for this input, so lo - 1 cannot borrow
    let s = isqrt_u256(lo - 1, hi);
    assert(s == 239_999_999_999_999_999_999, "isqrt(s^2 - 1) == s - 1");
}

// ----- get_amount_out ----- //
// -------------------------- //

// zero fee, constant-product identity: in=1000 into 1000/1000 reserves.
// aif = 1000*10000 = 1e7; denom = 1000*10000 + 1e7 = 2e7; out = floor(1e7*1000/2e7) = 500.
// check: k holds -> (1000+1000)*(1000-500) == 1000*1000.
#[test]
fn test_get_amount_out_zero_fee() {
    assert(get_amount_out(1000, 1000, 1000, 0) == 500, "== 500");
}

// 50% fee: factor 5000. in=1000 -> aif=5e6; denom=1000*10000+5e6=1.5e7;
// out = floor(5e6 * 3000 / 1.5e7) = floor(1.5e10/1.5e7) = 1000 exact.
#[test]
fn test_get_amount_out_with_fee() {
    assert(get_amount_out(1000, 1000, 3000, 5000) == 1000, "== 1000");
}

// 256-bit path, zero fee: 100e18 into 100e18/100e18.
// aif=1e24; denom=2e24; out=floor(1e24*100e18/2e24)=50e18. aif*reserve_out=1e44 overflows u128 -> exercises mul_div.
#[test]
fn test_get_amount_out_overflow_path() {
    let r = get_amount_out(
        100_000_000_000_000_000_000,
        100_000_000_000_000_000_000,
        100_000_000_000_000_000_000,
        0,
    );
    assert(r == 50_000_000_000_000_000_000, "== 50e18");
}
