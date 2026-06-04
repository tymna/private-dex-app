use crate::test::utils;
use aztec::protocol::address::AztecAddress;
use lp_token::LiquidityToken;

global TRANSFER_NONCE: Field = 1;
global MINIMUM_LIQUIDITY: u128 = 1_000;

// ----- happy paths ----- //
// ----------------------- //

// remove all of the user's shares from a freshly seeded 500:500 pool.
// because reserve == supply == 500e18, the proportional payout (shares * reserve / supply) equals
// the shares burned exactly, so the user reclaims their whole principal minus the MIN_LIQUIDITY dust
// that was locked on the initial deposit. supply collapses back down to exactly MIN_LIQUIDITY.
#[test]
unconstrained fn test_remove_liquidity() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    // --- state after the seed add ---
    let before = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        user,
    );

    // the user holds every circulating share; the rest is the locked MIN_LIQUIDITY
    assert(
        before.account_lp_shares == before.lp_total_supply - MINIMUM_LIQUIDITY,
        "user holds all non-locked shares",
    );

    // 1:1 pool -> payout == shares burned
    let user_shares = before.account_lp_shares;
    let expected0 = user_shares;
    let expected1 = user_shares;

    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user, // provider (burns shares)
        user, // to (receives the underlying)
        user_shares,
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    let after = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        user,
    );

    // shares fully burned
    assert(after.account_lp_shares == 0, "user burned all shares");

    // supply drops by exactly the burned shares -> only MIN_LIQUIDITY remains
    assert(
        after.lp_total_supply == before.lp_total_supply - user_shares,
        "supply reduced by burned shares",
    );
    assert(after.lp_total_supply == MINIMUM_LIQUIDITY, "only the locked MIN_LIQUIDITY remains");

    // reserves drop by the paid-out amounts
    assert(after.reserve0 == before.reserve0 - expected0, "reserve0 reduced by payout");
    assert(after.reserve1 == before.reserve1 - expected1, "reserve1 reduced by payout");

    // amm's public token balance stays in sync with the reserves it paid from
    assert(after.amm_token0 == before.amm_token0 - expected0, "amm paid out token0");
    assert(after.amm_token1 == before.amm_token1 - expected1, "amm paid out token1");

    // user receives the underlying as private notes
    assert(after.account_token0 == before.account_token0 + expected0, "user got token0 back");
    assert(after.account_token1 == before.account_token1 + expected1, "user got token1 back");
}

// burning 100% of a provider's shares can never drain the pool: the MIN_LIQUIDITY shares minted
// to the zero address on the initial deposit are unowned and unredeemable, so total supply floors
// at MIN_LIQUIDITY and a proportional slice of each reserve stays locked forever. on this 1:1
// 500:500 pool that locked slice is exactly MIN_LIQUIDITY (1000 wei) of each token.
#[test]
unconstrained fn test_remove_all_liquidity_leaves_locked_minimum() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    let lp_token = LiquidityToken::at(lp_token_address);

    let before = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        user,
    );

    // the locked MIN_LIQUIDITY was minted to the zero address on the initial deposit
    let zero_shares_before: u128 =
        env.view_public(lp_token.balance_of_public(AztecAddress::zero()));
    assert(zero_shares_before == MINIMUM_LIQUIDITY, "zero address holds the locked minimum");

    // burn every share the user owns
    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user, // provider
        user, // to
        before.account_lp_shares,
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    let after = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        user,
    );

    // user is fully out
    assert(after.account_lp_shares == 0, "user burned all shares");

    // supply floors at MIN_LIQUIDITY -> the pool is never fully drained
    assert(after.lp_total_supply == MINIMUM_LIQUIDITY, "supply floors at the locked minimum");

    // the locked shares' proportional reserves remain (1:1 pool -> 1000 wei each), owned by no one
    assert(after.reserve0 == MINIMUM_LIQUIDITY, "reserve0 locked at the minimum's share");
    assert(after.reserve1 == MINIMUM_LIQUIDITY, "reserve1 locked at the minimum's share");

    // amm public balances stay in sync with the locked reserves
    assert(after.amm_token0 == MINIMUM_LIQUIDITY, "amm still holds the locked token0");
    assert(after.amm_token1 == MINIMUM_LIQUIDITY, "amm still holds the locked token1");

    // the locked shares are untouched and remain with the zero address forever
    let zero_shares_after: u128 = env.view_public(lp_token.balance_of_public(AztecAddress::zero()));
    assert(zero_shares_after == MINIMUM_LIQUIDITY, "locked shares remain with the zero address");
}

// to != provider: the provider's LP shares are burned, but the underlying tokens are delivered to a
// different recipient (owner). proves the `to` param routes the payout independently of who funds the burn.
#[test]
unconstrained fn test_remove_liquidity_underlying_to_other_recipient() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    let user_before = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        user,
    );
    let owner_before = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        owner,
    );

    let user_shares = user_before.account_lp_shares;
    // 1:1 pool -> payout == shares burned
    let expected0 = user_shares;
    let expected1 = user_shares;

    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user, // provider (burns shares)
        owner, // to (receives the underlying)
        user_shares,
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );

    let user_after = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        user,
    );
    let owner_after = utils::snapshot(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        lp_token_address,
        owner,
    );

    // the provider's shares are burned
    assert(user_after.account_lp_shares == 0, "provider burned all shares");
    assert(
        user_after.lp_total_supply == user_before.lp_total_supply - user_shares,
        "supply reduced by burned shares",
    );

    // the underlying goes to the recipient, not the provider
    assert(
        owner_after.account_token0 == owner_before.account_token0 + expected0,
        "recipient got token0",
    );
    assert(
        owner_after.account_token1 == owner_before.account_token1 + expected1,
        "recipient got token1",
    );

    // the provider funded the burn but received none of the underlying
    assert(user_after.account_token0 == user_before.account_token0, "provider got no token0");
    assert(user_after.account_token1 == user_before.account_token1, "provider got no token1");
}

// ----- failures ----- //
// --------------------- //

// [1] slippage: redeeming 100e18 shares from a 1:1 500:500 pool pays out 100e18 token0,
// so amount0_min = 200e18 (above the payout) reverts in the public step.
#[test(should_fail_with = "amount0 to return is less than minimum")]
unconstrained fn test_remove_liquidity_slippage_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user,
        user,
        100_000_000_000_000_000_000, // 100e18 shares
        200_000_000_000_000_000_000, // amount0_min > payout (100e18) -> reverts
        1, // amount1_min
        TRANSFER_NONCE,
    );
}

// [2] shares == 0 is rejected up front in the private step (before any transfer).
#[test(should_fail_with = "shares must be > 0")]
unconstrained fn test_remove_liquidity_zero_shares_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user,
        user,
        0, // shares == 0 -> reverts
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );
}

// [3] a zero min is rejected (mirrors add_liquidity's guard). this is what guarantees the public
// step never completes a partial note with a 0 payout.
#[test(should_fail_with = "amounts must be > 0")]
unconstrained fn test_remove_liquidity_zero_min_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user,
        user,
        100_000_000_000_000_000_000, // valid shares
        0, // amount0_min == 0 -> reverts
        1, // amount1_min
        TRANSFER_NONCE,
    );
}

// [4] redeeming more shares than the provider holds fails when the AMM pulls the LP shares into
// its public balance: the provider's private balance is too low to cover the transfer.
#[test(should_fail_with = "Balance too low")]
unconstrained fn test_remove_liquidity_insufficient_shares_reverts() {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _, _, _) =
        utils::deploy_amm_and_add_liquidity();

    // user holds 500e18 - MIN_LIQUIDITY shares; ask for far more than that
    utils::remove_liquidity(
        &mut env,
        amm_address,
        lp_token_address,
        user,
        user,
        1_000_000_000_000_000_000_000, // 1000e18 > held -> transfer fails
        1, // amount0_min
        1, // amount1_min
        TRANSFER_NONCE,
    );
}
