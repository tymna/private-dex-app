use crate::test::utils;

global TRANSFER_NONCE: Field = 1;
global MINIMUM_LIQUIDITY: u128 = 1_000;

// ----- happy paths ----- //
// ----------------------- //

// initial deposit into an empty pool: supply = sqrt(a0*a1), user gets supply - MIN_LIQUIDITY
#[test]
unconstrained fn test_add_initial_liquidity() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();
    let (amount0_max, amount1_max, amount0_min, amount1_min) = utils::amounts_to_add();

    let before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);
    assert(before.lp_total_supply == 0, "supply should be 0 before adding liquidity");

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        amount0_max,
        amount1_max,
        amount0_min,
        amount1_min,
        TRANSFER_NONCE,
    );

    let after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    assert(after.lp_total_supply == amount0_max, "supply == sqrt(a0*a1)");
    assert(
        after.account_lp_shares == after.lp_total_supply - MINIMUM_LIQUIDITY,
        "user shares == supply - locked",
    );
    assert(after.amm_token0 == amount0_max, "amm holds all token0");
    assert(after.amm_token1 == amount1_max, "amm holds all token1");
}

// off-ratio deposit on a 1:1 pool: provide 200/100, token1 limits so used0 = used1 = 100e18
// and the 100e18 token0 excess is refunded to `to`
#[test]
unconstrained fn test_add_liquidity_off_ratio_refunds_excess() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();
    let (amount0_max, amount1_max, amount0_min, amount1_min) = utils::amounts_to_add();

    // seed pool at 500:500
    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        amount0_max,
        amount1_max,
        amount0_min,
        amount1_min,
        TRANSFER_NONCE,
    );

    let before =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    let amount0_max_2: u128 = 200_000_000_000_000_000_000; // 200e18
    let amount1_max_2: u128 = 100_000_000_000_000_000_000; // 100e18
    let amount0_min_2: u128 = 90_000_000_000_000_000_000; // 90e18 (<= used)
    let amount1_min_2: u128 = 90_000_000_000_000_000_000; // 90e18

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        amount0_max_2,
        amount1_max_2,
        amount0_min_2,
        amount1_min_2,
        TRANSFER_NONCE,
    );

    let after =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    let expected_used: u128 = 100_000_000_000_000_000_000; // 100e18

    // used == reserve delta
    let used0 = after.reserve0 - before.reserve0;
    let used1 = after.reserve1 - before.reserve1;
    assert(used0 == expected_used, "used0 == 100e18");
    assert(used1 == expected_used, "used1 == 100e18");

    // net spend == used (token0 excess refunded, token1 fully used)
    assert(after.account_token0 == before.account_token0 - used0, "token0 refunded");
    assert(after.account_token1 == before.account_token1 - used1, "token1 fully used");

    // shares minted proportionally and credited to the user
    let minted = after.lp_total_supply - before.lp_total_supply;
    assert(minted == expected_used, "minted == 100e18");
    assert(
        after.account_lp_shares - before.account_lp_shares == minted,
        "user got all minted shares",
    );
}

// to != from: user funds the deposit with their own tokens but directs the shares to owner
#[test]
unconstrained fn test_add_liquidity_shares_to_other_recipient() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();
    let (amount0_max, amount1_max, amount0_min, amount1_min) = utils::amounts_to_add();

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user, // provider (caller, tokens spent)
        owner, // to (receives shares)
        amount0_max,
        amount1_max,
        amount0_min,
        amount1_min,
        TRANSFER_NONCE,
    );

    let recipient =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, owner);
    let funder =
        utils::snapshot(&mut env, amm_address, token0_address, token1_address, lp_token_address, user);

    // shares went to owner, not the funder
    assert(
        recipient.account_lp_shares == recipient.lp_total_supply - MINIMUM_LIQUIDITY,
        "recipient (owner) got the shares",
    );
    assert(funder.account_lp_shares == 0, "funder (user) got no shares");
}

// ----- failures  ----- //
// --------------------- //

// [1] slippage: on a 500:500 pool a 200/100 deposit only uses 100e18 token0, so amount0_min = 150e18 reverts
#[test(should_fail_with = "not enough amount0 provided")]
unconstrained fn test_add_liquidity_slippage_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();
    let (amount0_max, amount1_max, amount0_min, amount1_min) = utils::amounts_to_add();

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        amount0_max,
        amount1_max,
        amount0_min,
        amount1_min,
        TRANSFER_NONCE,
    );

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        200_000_000_000_000_000_000, // amount0_max
        100_000_000_000_000_000_000, // amount1_max
        150_000_000_000_000_000_000, // amount0_min > used0 (100e18) -> reverts
        90_000_000_000_000_000_000, // amount1_min
        TRANSFER_NONCE,
    );
}

// [2] initial deposit must mint more than MIN_LIQUIDITY: sqrt(1000*1000) == 1000 == MIN_LIQUIDITY -> reverts
#[test(should_fail_with = "not enough for initial deposit")]
unconstrained fn test_initial_deposit_too_small_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        1_000, // amount0_max
        1_000, // amount1_max
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );
}

// [3] dust deposit: on an imbalanced 800:200 pool (supply 400e18) a 1-wei token0 deposit rounds to 0 shares
#[test(should_fail_with = "not enough provided for any shares")]
unconstrained fn test_add_liquidity_too_small_for_shares_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();

    // seed imbalanced pool so reserve0 > supply
    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        800_000_000_000_000_000_000, // 800e18
        200_000_000_000_000_000_000, // 200e18
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        1, // amount0_max -> rounds to 0 shares
        1, // amount1_max
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );
}

// [4] input validation: amount0_min > amount0_max reverts before any transfer
#[test(should_fail_with = "min amount0 must be <= max amount0")]
unconstrained fn test_add_liquidity_min_exceeds_max_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, mint0_amount, mint1_amount) =
        utils::deploy_amm_and_mint();

    utils::add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user, // to
        100_000_000_000_000_000_000, // amount0_max
        500_000_000_000_000_000_000, // amount1_max
        200_000_000_000_000_000_000, // amount0_min > max0 -> reverts
        400_000_000_000_000_000_000, // amount1_min
        TRANSFER_NONCE,
    );
}
