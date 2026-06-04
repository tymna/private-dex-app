use crate::AMM;
use lp_token::LiquidityToken;
use token::Token;

use aztec::{
    protocol::address::AztecAddress,
    test::helpers::{authwit as authwits_cheatcodes, test_environment::TestEnvironment},
};

global TRANSFER_NONCE: Field = 1;

// ----- deploy ----- //
// ------------------ //
pub unconstrained fn deploy_amm_contract() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let owner = env.create_contract_account();
    let user = env.create_contract_account();

    // deoloy token0
    let token0_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        Token::interface().constructor_with_minter(
            "Token00000000000000000000000000",
            "TK00000000000000000000000000000",
            18,
            owner,
        ),
    );

    // deploy token1
    let token1_address = env.deploy("@token_contract/Token").with_public_initializer(
        owner,
        Token::interface().constructor_with_minter(
            "Token11111111111111111111111111",
            "TK11111111111111111111111111111",
            18,
            owner,
        ),
    );

    // deploy AMM with addresses of the above contracts
    let amm_address = env.deploy("@amm/AMM").with_public_initializer(
        owner,
        AMM::interface().constructor(token0_address, token1_address, 300),
    );

    // deploy lp token
    let lp_token_address = env.deploy("@lp_token/LiquidityToken").with_public_initializer(
        owner,
        LiquidityToken::interface().constructor(
            "LPToken000000000000000000000000",
            "LP00000000000000000000000000000",
            18,
            amm_address,
        ),
    );

    // initialize lp token
    let amm = AMM::at(amm_address);
    env.call_public(owner, amm.set_lp_token(lp_token_address));

    (env, owner, user, amm_address, token0_address, token1_address, lp_token_address)
}

/// Deploys the AMM and mints `1000e18` of each token to `user`'s private balance.
/// Returns the deployment plus the minted amount for token0 and token1.
pub unconstrained fn deploy_amm_and_mint() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, u128, u128) {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address) =
        deploy_amm_contract();

    // owner is the minter (set via constructor_with_minter)
    let mint_amount: u128 = 1_000_000_000_000_000_000_000; // 1000 * 10^18
    mint_to_private(&mut env, token0_address, owner, user, mint_amount);
    mint_to_private(&mut env, token1_address, owner, user, mint_amount);

    (
        env, owner, user, amm_address, token0_address, token1_address, lp_token_address,
        mint_amount, mint_amount,
    )
}

/// Full initial state: deploy, mint to `user`, then add liquidity so the pool has reserves.
/// `user` is both the provider and the share recipient. Returns the deployment, the mint amount,
/// and the amounts added to the pool.
pub unconstrained fn deploy_amm_and_add_liquidity() -> (TestEnvironment, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, AztecAddress, u128, u128, u128, u128) {
    let (mut env, owner, user, amm_address, token0_address, token1_address, lp_token_address, _, _) =
        deploy_amm_and_mint();

    let (amount0_max, amount1_max, amount0_min, amount1_min) = amounts_to_add();

    add_liquidity(
        &mut env,
        amm_address,
        token0_address,
        token1_address,
        user,
        user,
        amount0_max,
        amount1_max,
        amount0_min,
        amount1_min,
        TRANSFER_NONCE,
    );

    (
        env, owner, user, amm_address, token0_address, token1_address, lp_token_address,
        amount0_max, amount1_max, amount0_min, amount1_min,
    )
}

// ----- add liquidity ----- //
// ------------------------- //
pub unconstrained fn add_liquidity(
    env: &mut TestEnvironment,
    amm_address: AztecAddress,
    token0_address: AztecAddress,
    token1_address: AztecAddress,
    provider: AztecAddress,
    to: AztecAddress,
    amount0_max: u128,
    amount1_max: u128,
    amount0_min: u128,
    amount1_min: u128,
    transfer_nonce: Field,
) {
    let amm = AMM::at(amm_address);

    authwits_cheatcodes::add_private_authwit_from_call(
        *env,
        provider,
        amm_address,
        Token::at(token0_address).transfer_private_to_public(
            provider,
            amm_address,
            amount0_max,
            transfer_nonce,
        ),
    );

    authwits_cheatcodes::add_private_authwit_from_call(
        *env,
        provider,
        amm_address,
        Token::at(token1_address).transfer_private_to_public(
            provider,
            amm_address,
            amount1_max,
            transfer_nonce,
        ),
    );

    let add_liquidity_interface = amm.add_liquidity(
        to,
        amount0_max,
        amount1_max,
        amount0_min,
        amount1_min,
        transfer_nonce,
    );

    env.call_private(provider, add_liquidity_interface);
}

// ----- remove liquidity ----- //
// ---------------------------- //
pub unconstrained fn remove_liquidity(
    env: &mut TestEnvironment,
    amm_address: AztecAddress,
    lp_token_address: AztecAddress,
    provider: AztecAddress,
    to: AztecAddress,
    shares: u128,
    amount0_min: u128,
    amount1_min: u128,
    transfer_nonce: Field,
) {
    let amm = AMM::at(amm_address);

    // the AMM pulls the provider's LP shares into its public balance, so the provider must
    // authorize that exact transfer (same shape as the token authwits in add_liquidity).
    authwits_cheatcodes::add_private_authwit_from_call(
        *env,
        provider,
        amm_address,
        LiquidityToken::at(lp_token_address).transfer_private_to_public(
            provider,
            amm_address,
            shares,
            transfer_nonce,
        ),
    );

    let remove_liquidity_interface =
        amm.remove_liquidity(to, shares, amount0_min, amount1_min, transfer_nonce);

    env.call_private(provider, remove_liquidity_interface);
}

// ----- swap ----- //
// ---------------- //
/// Performs an exact-input swap as `provider`: spends `amount_in` of `token_in_address`,
/// sends the output (>= `amount_out_min`) to `to`.
///
/// - `provider` is the caller whose private input notes are spent (msg_sender in the contract).
/// - `to` receives the output as a private note; pass `provider` for a self-swap.
/// - `token_in_address` must be one of the pool's two tokens; it decides the swap direction.
/// - mirrors the production call path: authorize the input pull, then call `swap` privately.
pub unconstrained fn swap(
    env: &mut TestEnvironment,
    amm_address: AztecAddress,
    token_in_address: AztecAddress,
    provider: AztecAddress,
    to: AztecAddress,
    amount_in: u128,
    amount_out_min: u128,
    transfer_nonce: Field,
) {
    let amm = AMM::at(amm_address);

    // The AMM (not the provider) is msg_sender to the token, so it pulls the input via
    // transfer_private_to_public on the provider's behalf -> the provider must pre-authorize
    // that exact call. Only ONE authwit is needed: the input leg. The output is paid by the
    // AMM out of its own public balance into a commitment, so it needs no provider approval.
    authwits_cheatcodes::add_private_authwit_from_call(
        *env,
        provider,
        amm_address,
        Token::at(token_in_address).transfer_private_to_public(
            provider,
            amm_address,
            amount_in,
            transfer_nonce,
        ),
    );

    // Private entrypoint: opens the output commitment and enqueues the public _swap that prices
    // it against the reserves. Called as `provider` so msg_sender == the funder.
    let swap_interface =
        amm.swap(to, token_in_address, amount_in, amount_out_min, transfer_nonce);

    env.call_private(provider, swap_interface);
}

// ----- snapshot ----- //
// --------------------- //
/// A point-in-time view of the full pool state an op can move: the reserves, one account's
/// PRIVATE token + LP balances, the AMM's PUBLIC token custody, and the LP total supply.
/// Take one before and one after an action and assert on the deltas. (For swaps, the two LP
/// fields should stay unchanged - a useful free invariant.)
pub struct PoolSnapshot {
    pub reserve0: u128,
    pub reserve1: u128,
    pub account_token0: u128,
    pub account_token1: u128,
    pub amm_token0: u128,
    pub amm_token1: u128,
    pub account_lp_shares: u128,
    pub lp_total_supply: u128,
}

pub unconstrained fn snapshot(
    env: &mut TestEnvironment,
    amm_address: AztecAddress,
    token0_address: AztecAddress,
    token1_address: AztecAddress,
    lp_token_address: AztecAddress,
    account: AztecAddress,
) -> PoolSnapshot {
    let amm = AMM::at(amm_address);
    let token0 = Token::at(token0_address);
    let token1 = Token::at(token1_address);
    let lp_token = LiquidityToken::at(lp_token_address);

    PoolSnapshot {
        reserve0: env.view_public(amm.reserve0()),
        reserve1: env.view_public(amm.reserve1()),
        account_token0: env.execute_utility(token0.balance_of_private(account)),
        account_token1: env.execute_utility(token1.balance_of_private(account)),
        amm_token0: env.view_public(token0.balance_of_public(amm_address)),
        amm_token1: env.view_public(token1.balance_of_public(amm_address)),
        account_lp_shares: env.execute_utility(lp_token.balance_of_private(account)),
        lp_total_supply: env.view_public(lp_token.total_supply()),
    }
}

// ----- helpers ----- //
// ------------------- //
/// Mints `amount` of `token_address` to `to`'s private balance, called as `minter`.
pub unconstrained fn mint_to_private(
    env: &mut TestEnvironment,
    token_address: AztecAddress,
    minter: AztecAddress,
    to: AztecAddress,
    amount: u128,
) {
    let token = Token::at(token_address);
    env.call_private(minter, token.mint_to_private(to, amount));
}

pub unconstrained fn amounts_to_add() -> (u128, u128, u128, u128) {
    let amount0_max: u128 = 500_000_000_000_000_000_000; // 500 * 10^18
    let amount1_max: u128 = 500_000_000_000_000_000_000; // 500 * 10^18
    let amount0_min: u128 = 400_000_000_000_000_000_000; // 400 * 10^18
    let amount1_min: u128 = 400_000_000_000_000_000_000; // 400 * 10^18

    (amount0_max, amount1_max, amount0_min, amount1_min)
}
