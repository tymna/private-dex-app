use aztec::protocol::{address::AztecAddress, traits::{Deserialize, Packable, Serialize}};
use std::meta::derive;

#[derive(Deserialize, Eq, Packable, Serialize)]
    pub struct Config {
    pub token0: AztecAddress,
    pub token1: AztecAddress,
    // deployer captured at construction; only this account may wire set_lp_token.
    pub admin: AztecAddress,
}