use crate::{test::utils, LiquidityToken};
use aztec::protocol::address::AztecAddress;

#[test]
unconstrained fn test_mint_to_zero_address() {
    let (env, lp_token_address, minter) = utils::setup();

    env.call_private(minter, LiquidityToken::at(lp_token_address).mint_to_private(AztecAddress::zero(), 1000));

    let total_supply = env.view_public(LiquidityToken::at(lp_token_address).total_supply());
    assert(total_supply == 1000, "Total supply should be 1000 after mint");

    let balance = env.execute_utility(LiquidityToken::at(lp_token_address).balance_of_private(AztecAddress::zero()));
    assert(balance == 1000, "Zero address should hold 1000 LP tokens");
}
