use crate::LiquidityToken;
use aztec::{protocol::address::AztecAddress, test::helpers::test_environment::TestEnvironment};

pub unconstrained fn setup() -> (TestEnvironment, AztecAddress, AztecAddress) {
    let mut env = TestEnvironment::new();
    let minter = env.create_light_account();

    let initializer = LiquidityToken::interface().constructor(
        "LPToken000000000000000000000000",
        "LP00000000000000000000000000000",
        18,
        minter,
    );
    let lp_token_address =
        env.deploy("@lp_token/LiquidityToken").with_public_initializer(minter, initializer);

    (env, lp_token_address, minter)
}
