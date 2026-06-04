// Multi-operation lifecycle tests: exercise add/swap/remove in sequence to prove the operations
// compose (state persists across them, fees accrue to LPs, no value leaks). These assert robust
// directional/invariant properties; the few exact numbers are independently computed (see comments),
// not re-derived from the contract.
use crate::test::utils;

global TRANSFER_NONCE: Field = 1;
global MINIMUM_LIQUIDITY: u128 = 1_000;
global AMOUNT_IN: u128 = 100_000_000_000_000_000_000; // 100e18
global EXPECTED_OUT: u128 = 81_239_530_988_274_706_867; // 100e18 in on a 500e18:500e18 pool, fee 300
global PRINCIPAL_SUM: u128 = 1_000_000_000_000_000_000_000; // 500e18 + 500e18 deposited per LP

// add -> a third party trades -> the sole LP removes everything and ends up with MORE than its
// 1000e18 principal: it earned the swap fee. (independently: post-swap reserves sum to 1018.76e18,
// and the LP owns ~all of the pool.)
#[test]
unconstrained fn test_flow_add_swap_remove_lp_earns_fee() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity(); // user is the sole LP; pool seeded 500e18:500e18

    // a separate trader (owner) gets token0 to swap with
    utils::mint_to_private(&mut env, token0_address, owner, owner, AMOUNT_IN);

    // LP balances before the trade (user already spent 500e18 of each seeding the pool)
    let lp_before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // owner trades token0 -> token1; the fee stays in the pool, growing reserves
    utils::swap(&mut env, amm_address, token0_address, owner, owner, AMOUNT_IN, 1, TRANSFER_NONCE);

    // the sole LP withdraws everything
    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user, // provider (burns shares)
        user, // to
        lp_before.account_lp_shares,
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    let lp_after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // pool drained back down to the locked minimum
    assert(lp_after.lp_total_supply == MINIMUM_LIQUIDITY, "supply floors at MIN_LIQUIDITY");
    assert(lp_after.account_lp_shares == 0, "LP burned all shares");

    // recovered more than the 1000e18 principal -> the LP captured the swap fee
    let recovered0 = lp_after.account_token0 - lp_before.account_token0;
    let recovered1 = lp_after.account_token1 - lp_before.account_token1;
    assert(recovered0 + recovered1 > PRINCIPAL_SUM, "LP recovered principal + fee");
}

// round-trip: swap token0 -> token1, then swap all of it back token1 -> token0. The trader ends with
// the same token1 but LESS token0 than it started: the two fees eat the round trip (no free arb).
// (independently: 100e18 -> ~95.03e18 back.)
#[test]
unconstrained fn test_flow_round_trip_swap_loses_to_fees() {
    let (mut env, _owner, user, amm_address, token0_address, token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    let before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // token0 -> token1
    utils::swap(&mut env, amm_address, token0_address, user, user, AMOUNT_IN, 1, TRANSFER_NONCE);
    let mid =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);
    let got_token1 = mid.account_token1 - before.account_token1;

    // swap exactly what we received back, token1 -> token0 (distinct nonce: 2nd authwit, same caller)
    utils::swap(&mut env, amm_address, token1_address, user, user, got_token1, 1, TRANSFER_NONCE + 1);
    let after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // token1 is back to the starting balance (we swapped exactly what we received)
    assert(after.account_token1 == before.account_token1, "all token1 swapped back");
    // ...but we end with less token0 than we started: the two 3% fees ate the round trip
    assert(after.account_token0 < before.account_token0, "round-trip loses token0 to fees");
}

// two identical same-direction swaps: the second returns strictly less than the first, because the
// first already moved reserves against the trader. (independently: 81.24e18 then 58.28e18.)
#[test]
unconstrained fn test_flow_sequential_swaps_worsen_price() {
    let (mut env, _owner, user, amm_address, token0_address, token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    let s0 =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);
    utils::swap(&mut env, amm_address, token0_address, user, user, AMOUNT_IN, 1, TRANSFER_NONCE);
    let s1 =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);
    utils::swap(&mut env, amm_address, token0_address, user, user, AMOUNT_IN, 1, TRANSFER_NONCE + 1);
    let s2 =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    let out_a = s0.reserve1 - s1.reserve1;
    let out_b = s1.reserve1 - s2.reserve1;

    assert(out_a == EXPECTED_OUT, "first swap output == oracle");
    assert(out_b < out_a, "second identical swap returns less (price moved)");
}

// two equal LPs, one trade: the second LP (a pure LP that never trades) still withdraws more than
// its 1000e18 principal -> fees distribute pro-rata to all share holders. (independently: ~1005.79e18.)
#[test]
unconstrained fn test_flow_two_lps_share_fees_pro_rata() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, amount0, amount1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity(); // user seeded 500e18:500e18

    // owner becomes a second, equal LP: mint it 500e18 of each, then add at the current 1:1 ratio
    utils::mint_to_private(&mut env, token0_address, owner, owner, amount0);
    utils::mint_to_private(&mut env, token1_address, owner, owner, amount1);
    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        owner, // provider
        owner, // to
        amount0,
        amount1,
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    // baseline AFTER the deposit: owner holds its shares and ~0 loose tokens
    let owner_baseline =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, owner);

    // user (also an LP) trades; the fee accrues to the whole pool, i.e. to both LPs
    utils::swap(&mut env, amm_address, token0_address, user, user, AMOUNT_IN, 1, TRANSFER_NONCE);

    // the pure LP (owner) withdraws everything
    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        owner, // provider
        owner, // to
        owner_baseline.account_lp_shares,
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    let owner_final =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, owner);

    // recovered more than the 1000e18 it deposited, despite never trading -> pro-rata fee share
    let recovered0 = owner_final.account_token0 - owner_baseline.account_token0;
    let recovered1 = owner_final.account_token1 - owner_baseline.account_token1;
    assert(recovered0 + recovered1 > PRINCIPAL_SUM, "pure LP earned pro-rata fees");
}
