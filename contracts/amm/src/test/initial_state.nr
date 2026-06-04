use crate::{test::utils, AMM};
use lp_token::LiquidityToken;

#[test]
unconstrained fn test_initial_state() {
    let (mut env, _owner, _user, amm_address, token0_address, token1_address, lp_token_address) =
        utils::deploy_amm_contract();

    let amm = AMM::at(amm_address);

    // config: token addresses stored in the right slots
    assert(env.view_public(amm.token0()).eq(token0_address), "token0 mismatch");
    assert(env.view_public(amm.token1()).eq(token1_address), "token1 mismatch");

    // lp_token wired via set_lp_token
    assert(env.view_public(amm.lp_token_address()).eq(lp_token_address), "lp_token mismatch");

    let lp_token = LiquidityToken::at(lp_token_address);
    assert(env.view_public(lp_token.minter()).eq(amm_address), "lp token minter mismatch"   );
    assert(env.view_public(lp_token.total_supply()) == 0 as u128, "lp token total supply not zero");

    // reserves start empty
    assert(env.view_public(amm.reserve0()) == 0 as u128, "reserve0 not zero");
    assert(env.view_public(amm.reserve1()) == 0 as u128, "reserve1 not zero");

    // fee rate set by constructor (300)
    assert(env.view_public(amm.fee_rate()) == 300, "fee_rate mismatch");
}

// only the deployer (admin) may wire the lp_token. a non-admin caller is rejected by the
// admin gate, which is the first line of set_lp_token (so it fires before the once-only
// initialize check). `user` is a separate account from the deploying `owner`.
#[test(should_fail_with = "only admin")]
unconstrained fn test_set_lp_token_only_admin() {
    let (mut env, _owner, user, amm_address, _token0_address, _token1_address, lp_token_address) =
        utils::deploy_amm_contract();

    let amm = AMM::at(amm_address);
    env.call_public(user, amm.set_lp_token(lp_token_address));
}
