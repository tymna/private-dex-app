use crate::{AMM, test::utils};

global TRANSFER_NONCE: Field = 1;

// Pool is seeded 500e18:500e18 with fee_rate 300 (3%). For a 100e18 input the output is computed
// independently (NOT by re-running the contract formula):
//   aif   = 100e18 * (10000 - 300)      = 9.7e23
//   denom = 500e18 * 10000 + aif        = 5.97e24
//   out   = floor(aif * 500e18 / denom) = 81239530988274706867
// the pool is symmetric, so both directions yield the same EXPECTED_OUT.
global AMOUNT_IN: u128 = 100_000_000_000_000_000_000; // 100e18
global AMOUNT_OUT_MIN: u128 = 80_000_000_000_000_000_000; // 80e18, comfortably below expected
global EXPECTED_OUT: u128 = 81_239_530_988_274_706_867;

// ----- happy paths ----- //
// ----------------------- //

// token0 -> token1 self-swap. The exhaustive one: pin the exact output and check every observable
// (reserves, AMM public balances, caller's private balances) moves consistently with it.
#[test]
unconstrained fn test_swap_zero_for_one() {
    let (mut env, _owner, user, amm_address, token0_address, token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    let before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // swap token0 -> token1 (token_in == token0 => zero_for_one)
    utils::swap(
        &mut env,
        amm_address,
        token0_address, // token_in
        user, // provider (funds the swap)
        user, // to (self-swap)
        AMOUNT_IN,
        AMOUNT_OUT_MIN,
        TRANSFER_NONCE,
    );

    let after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // output matches the independent oracle, and the reserve delta agrees with it
    let amount_out = before.reserve1 - after.reserve1;
    assert(amount_out == EXPECTED_OUT, "amount_out == expected");

    // reserves: input side grows by the full input, output side shrinks by the output
    assert(after.reserve0 == before.reserve0 + AMOUNT_IN, "reserve0 += amount_in");
    assert(after.reserve1 == before.reserve1 - EXPECTED_OUT, "reserve1 -= amount_out");

    // caller: spent exactly amount_in of token0, received exactly amount_out of token1
    assert(after.account_token0 == before.account_token0 - AMOUNT_IN, "user spent amount_in token0");
    assert(
        after.account_token1 == before.account_token1 + EXPECTED_OUT,
        "user received amount_out token1",
    );

    // AMM public balances mirror the reserve moves (reserves stay in sync with custody)
    assert(after.amm_token0 == before.amm_token0 + AMOUNT_IN, "amm token0 += amount_in");
    assert(after.amm_token1 == before.amm_token1 - EXPECTED_OUT, "amm token1 -= amount_out");

    // a swap never touches LP state
    assert(after.lp_total_supply == before.lp_total_supply, "lp supply unchanged");
    assert(after.account_lp_shares == before.account_lp_shares, "lp shares unchanged");
}

// token1 -> token0 (the `else` branch: token_in == token1 => zero_for_one == false).
// the pool is symmetric (500e18:500e18), so the expected output is the same EXPECTED_OUT.
// this is the direction-mirror: it catches any reserve_in/reserve_out or token0/token1 swap-around bug.
#[test]
unconstrained fn test_swap_one_for_zero() {
    let (mut env, _owner, user, amm_address, token0_address, token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    let before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // swap token1 -> token0 (token_in == token1 => !zero_for_one)
    utils::swap(
        &mut env,
        amm_address,
        token1_address, // token_in
        user, // provider
        user, // to
        AMOUNT_IN,
        AMOUNT_OUT_MIN,
        TRANSFER_NONCE,
    );

    let after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // output comes from the reserve0 delta now (token0 is the OUTPUT side)
    let amount_out = before.reserve0 - after.reserve0;
    assert(amount_out == EXPECTED_OUT, "amount_out == expected");

    // reserves: input side (token1) grows, output side (token0) shrinks - mirror of test 1
    assert(after.reserve1 == before.reserve1 + AMOUNT_IN, "reserve1 += amount_in");
    assert(after.reserve0 == before.reserve0 - EXPECTED_OUT, "reserve0 -= amount_out");

    // caller: spent token1, received token0
    assert(after.account_token1 == before.account_token1 - AMOUNT_IN, "user spent amount_in token1");
    assert(
        after.account_token0 == before.account_token0 + EXPECTED_OUT,
        "user received amount_out token0",
    );

    // amm public balances mirror the reserve moves
    assert(after.amm_token1 == before.amm_token1 + AMOUNT_IN, "amm token1 += amount_in");
    assert(after.amm_token0 == before.amm_token0 - EXPECTED_OUT, "amm token0 -= amount_out");

    // a swap never touches LP state
    assert(after.lp_total_supply == before.lp_total_supply, "lp supply unchanged");
    assert(after.account_lp_shares == before.account_lp_shares, "lp shares unchanged");
}

// to != from: the funder (user) spends the input, the output note lands on a different recipient
// (owner). proves `to` routes the output independently of who funds the swap.
#[test]
unconstrained fn test_swap_output_to_other_recipient() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    let funder_before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);
    let recipient_before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, owner);

    // user funds a token0 -> token1 swap, output directed to owner
    utils::swap(
        &mut env,
        amm_address,
        token0_address, // token_in
        user, // provider (funds the swap)
        owner, // to (receives the output)
        AMOUNT_IN,
        AMOUNT_OUT_MIN,
        TRANSFER_NONCE,
    );

    let funder_after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);
    let recipient_after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, owner);

    // funder spent the input and received nothing
    assert(
        funder_after.account_token0 == funder_before.account_token0 - AMOUNT_IN,
        "funder spent amount_in token0",
    );
    assert(funder_after.account_token1 == funder_before.account_token1, "funder got no token1");

    // recipient received the output and spent nothing
    assert(
        recipient_after.account_token1 == recipient_before.account_token1 + EXPECTED_OUT,
        "recipient got amount_out token1",
    );
    assert(
        recipient_after.account_token0 == recipient_before.account_token0,
        "recipient spent no token0",
    );
}

// ----- failures ----- //
// --------------------- //

// [1] slippage: real output on the seeded 500:500 pool is ~81.2e18; demanding 90e18 reverts in
// the public step.
#[test(should_fail_with = "amount_out is less than minimum")]
unconstrained fn test_swap_slippage_reverts() {
    let (mut env, _owner, user, amm_address, token0_address, token1_address, _lp, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    utils::swap(
        &mut env,
        amm_address,
        token0_address,
        user,
        user,
        AMOUNT_IN,
        90_000_000_000_000_000_000, // amount_out_min 90e18 > real ~81.2e18 -> reverts
        TRANSFER_NONCE,
    );
}

// [2] token_in must be one of the pool tokens. The lp_token address is a real contract but not
// token0/token1, so the membership assert in the private step rejects it before any transfer.
// Call the contract directly (not utils::swap): the helper would first try to build an input
// authwit on the bogus token, which would fail before we reach the assert we're testing.
#[test(should_fail_with = "token_in must be either token0 or token1")]
unconstrained fn test_swap_bad_token_in_reverts() {
    let (mut env, _owner, user, amm_address, _token0_address, _token1_address, lp_token_address, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    let amm = AMM::at(amm_address);
    env.call_private(
        user,
        amm.swap(user, lp_token_address, AMOUNT_IN, AMOUNT_OUT_MIN, TRANSFER_NONCE),
    );
}

// [3] zero input is rejected up front in the private step.
#[test(should_fail_with = "amount_in must be > 0")]
unconstrained fn test_swap_zero_input_reverts() {
    let (mut env, _owner, user, amm_address, token0_address, token1_address, _lp, _a0, _a1, _m0, _m1) =
        utils::deploy_amm_and_add_liquidity();

    utils::swap(
        &mut env,
        amm_address,
        token0_address,
        user,
        user,
        0, // amount_in == 0 -> reverts
        AMOUNT_OUT_MIN,
        TRANSFER_NONCE,
    );
}

// [4] swapping into an empty pool: with no liquidity reserve_out == 0, so amount_out == 0 and the
// slippage assert (amount_out_min > 0) reverts in the public step. the tx is atomic, so the input
// pull rolls back too. uses deploy_amm_and_mint -> tokens minted to user, but the pool is NOT seeded.
#[test(should_fail_with = "amount_out is less than minimum")]
unconstrained fn test_swap_empty_pool_reverts() {
    let (mut env, _owner, user, amm_address, token0_address, _token1_address, _lp, _m0, _m1) =
        utils::deploy_amm_and_mint();

    utils::swap(
        &mut env,
        amm_address,
        token0_address,
        user,
        user,
        AMOUNT_IN,
        AMOUNT_OUT_MIN,
        TRANSFER_NONCE,
    );
}
