mod test;
mod config;
mod math;

use aztec::macros::aztec;

#[aztec]
contract AMM {
    // ----- imports ----- //
    // ------------------- //
    use aztec::{
        macros::{
            events::event,
            functions::{external, initializer, only_self, view},
            storage::storage,
        },
        protocol::address::AztecAddress,
        state_vars::{PublicImmutable, PublicMutable},
    };

    use crate::config::Config;
    use crate::math::{get_amount_out, isqrt_u256, mul_div, mul_u128_to_u256};

    use lp_token::LiquidityToken;
    use token::Token;

    global MIN_LIQUIDITY: u128 = 1000;

    // ----- storage ----- //
    // ------------------- //
    #[storage]
    struct Storage<Context> {
        config: PublicImmutable<Config, Context>,
        // lp_token is set in a second step (set_lp_token), because the AMM must exist
        // before the lp_token can be deployed with this AMM as its minter (avoids a
        // circular address dependency). PublicImmutable is once-only, so it can't be reset.
        lp_token: PublicImmutable<AztecAddress, Context>,
        // -------------------
        reserve0: PublicMutable<u128, Context>,
        reserve1: PublicMutable<u128, Context>,
        // -------------------
        fee_rate: PublicMutable<u32, Context>,
    }

    #[event]
    struct LiquidityAdded {
        amount0: u128,
        amount1: u128,
        shares: u128,
    }

    #[event]
    struct LiquidityRemoved {
        amount0: u128,
        amount1: u128,
        shares: u128,
    }

    #[event]
    struct Swapped {
        amount_in: u128,
        amount_out: u128,
        zero_for_one: bool,
    }

    // ----- constructor ----- //
    // ----------------------- //
    #[external("public")]
    #[initializer]
    fn constructor(token0: AztecAddress, token1: AztecAddress, fee_rate: u32) {
        assert(token0 != token1, "token addresses must be different");

        // lp_token is wired separately via set_lp_token (see storage comment).
        self.storage.config.initialize(Config { token0, token1, admin: self.msg_sender() });
        self.storage.fee_rate.write(fee_rate);
    }

    // Second deploy step: link the lp_token once it has been deployed with this AMM as minter.
    // - asserts the AMM is the lp_token's minter, so a misconfigured wiring fails loudly here
    //   instead of silently bricking add_liquidity later.
    // - lp_token is a once-only PublicImmutable, so this can run exactly once.
    // Only the deployer (captured in the constructor) may wire the lp_token. Without this,
    // an attacker could deploy their own LiquidityToken naming this AMM as minter and front-run
    // the real call; lp_token is once-only, so the AMM would be permanently bound to a token
    // contract the attacker controls (fake total_supply/mint/burn -> broken share math).
    #[external("public")]
    fn set_lp_token(lp_token: AztecAddress) {
        assert(self.msg_sender().eq(self.storage.config.read().admin), "only admin");

        let minter = self.view(LiquidityToken::at(lp_token).minter());
        assert(minter.eq(self.address), "AMM must be lp_token minter");

        self.storage.lp_token.initialize(lp_token);
    }

    // ----- private external ----- //
    // ---------------------------- //
    // private function for adding liquidity called by user, so the address remains private
    // but amounts are public (cause they affect reserves, which are public by design)
    // because of this, we need to do a two-step process and use partial notes
    // private:
    // -- we do checks and transfer amounts from user's private balance (notes)
    // -- and because reserves aren't known in this part, we store partial notes (commitments): 2 for token refunds + 1 for lp shares
    // in that way public can complete the note later, once all the values we need are processed
    // public:
    //  we need to enqueue the call to public function that will actually add liquidity and mint shares

    // the caller is always the liquidity provider: their private tokens are spent and `to` receives
    // the shares + refunds. there is no on-behalf-of `from` because you can never nullify another
    // account's private notes - a relayer can only ever fund a deposit with its OWN balance (and may
    // still direct the shares elsewhere via `to`). authwit_nonce scopes the token-transfer authwits.
    #[external("private")]
    fn add_liquidity(
        to: AztecAddress,
        amount0_max: u128, // amount that we are putting in
        amount1_max: u128,
        amount0_min: u128, // min amount that must go in for call to succeed
        amount1_min: u128,
        authwit_nonce: Field,
    ) {
        // --- PRIVATE --- //
        let from = self.msg_sender();

        // sanity checks
        assert(amount0_min <= amount0_max, "min amount0 must be <= max amount0");
        assert(amount1_min <= amount1_max, "min amount1 must be <= max amount1");
        assert((amount0_min > 0 as u128) & (amount1_min > 0 as u128), "amounts must be > 0");

        let config = self.storage.config.read();
        let token0 = Token::at(config.token0);
        let token1 = Token::at(config.token1);
        let lp_token = LiquidityToken::at(self.storage.lp_token.read());

        // transfer from user's private balance to pair's public balance (cause we need to know the reserves publicly)
        self.call(token0.transfer_private_to_public(from, self.address, amount0_max, authwit_nonce));
        self.call(token1.transfer_private_to_public(from, self.address, amount1_max, authwit_nonce));

        let token0_refund_commitment =
            self.call(token0.initialize_transfer_commitment(to, self.address));
        let token1_refund_commitment =
            self.call(token1.initialize_transfer_commitment(to, self.address));
        let shares_commitment =
            self.call(lp_token.initialize_transfer_commitment(to, self.address));

        // public func called from private -> must be enqueued
        self.enqueue_self._add_liquidity(
            token0_refund_commitment,
            token1_refund_commitment,
            shares_commitment,
            amount0_max,
            amount1_max,
            amount0_min,
            amount1_min,
        );
    }

    // first branch is for initial liquidity when pool is empty
    // so we can just put max provided amounts (no refunds needed), subtract initial liquidity that needs to be locked
    // and mint shares = sqrt(amount0 * amount1) - MIN_LIQUIDITY
    // that initial liquidity is locked by minting to zero address

    // second branch is when pool already have some liquidity, so we need to calculate
    // what amount of tokens we need to add based on current ratio of reserves
    // and then calculate shares
    // after that we calculate refunds based on how much was used

    // after the if/else (not inside either branch) we settle once: update reserves, mint shares,
    // and refund unused tokens - all driven by the values the branches decided
    // (for initial deposit there are no refunds)

    // refunds are executed by:
    // using function to transfer from public balance to commitment (partial note) that we stored in the first step of execution
    // balances are public, but recipients are private:
    // 'to' address is stored in commitment and they'll receive notes with refunds
    // if there's nothing to refund (refund == 0) we just skip it - the partial note
    // stays uncompleted in public storage, which is harmless (no tokens were owed)
    #[only_self]
    #[external("public")]
    fn _add_liquidity(
        token0_refund_commitment: Field,
        token1_refund_commitment: Field,
        shares_commitment: Field,
        amount0_max: u128,
        amount1_max: u128,
        amount0_min: u128,
        amount1_min: u128,
    ) {
        let config = self.storage.config.read();
        let token0 = Token::at(config.token0);
        let token1 = Token::at(config.token1);
        let lp_token = LiquidityToken::at(self.storage.lp_token.read());

        let reserve0 = self.storage.reserve0.read();
        let reserve1 = self.storage.reserve1.read();
        let lp_token_total_supply = self.view(lp_token.total_supply());

        let mut amount0_refund = 0 as u128;
        let mut amount1_refund = 0 as u128;

        let mut amount0_used = 0 as u128;
        let mut amount1_used = 0 as u128;

        let mut shares = 0 as u128;

        if (lp_token_total_supply == 0) {
            let (prod_lo, prod_hi) = mul_u128_to_u256(amount0_max, amount1_max);
            shares = isqrt_u256(prod_lo, prod_hi);
            assert(shares > MIN_LIQUIDITY, "not enough for initial deposit");
            shares = shares - MIN_LIQUIDITY;

            amount0_used = amount0_max;
            amount1_used = amount1_max;

            self.call(lp_token.mint_to_public(AztecAddress::zero(), MIN_LIQUIDITY));
        } else {
            // Naive `amount * supply / reserve` overflows u128 once operands exceed ~1.84e19
            // (about 18 whole tokens at 18 decimals). mul_div avoids this by:
            //   - doing the multiplication out-of-circuit at 256-bit precision (the hint),
            //   - verifying in-circuit with the floor-division identity a*b == q*c + r.
            // The final quotient still fits in u128, so the result is usable as a token amount.
            shares = std::cmp::min(
                mul_div(amount0_max, lp_token_total_supply, reserve0),
                mul_div(amount1_max, lp_token_total_supply, reserve1),
            );

            assert(shares > 0 as u128, "not enough provided for any shares");

            amount0_used = mul_div(shares, reserve0, lp_token_total_supply);
            amount1_used = mul_div(shares, reserve1, lp_token_total_supply);

            assert(amount0_used >= amount0_min, "not enough amount0 provided");
            assert(amount1_used >= amount1_min, "not enough amount1 provided");

            amount0_refund = amount0_max - amount0_used;
            amount1_refund = amount1_max - amount1_used;
        }

        self.storage.reserve0.write(reserve0 + amount0_used);
        self.storage.reserve1.write(reserve1 + amount1_used);

        self.call(lp_token.mint_public_to_commitment(shares_commitment, shares));

        if (amount0_refund > 0 as u128) {
            self.call(token0.transfer_public_to_commitment(
                self.address,
                token0_refund_commitment,
                amount0_refund,
                0,
            ));
        }

        if (amount1_refund > 0 as u128) {
            self.call(token1.transfer_public_to_commitment(
                self.address,
                token1_refund_commitment,
                amount1_refund,
                0,
            ));
        }

        self.emit(LiquidityAdded { amount0: amount0_used, amount1: amount1_used, shares: shares });
    }

    // this is just add_liquidity backwards. there you put two tokens in and got lp shares,
    // same as in add_liquidity: we can't see the reserves in the private part, so we move
    // the shares in, leave empty "commitments" for the tokens you're owed, and let the public
    // part fill in the real amounts and send them once it can read the reserves.

    // the caller is always the liquidity provider: their private LP shares are spent and `to` receives the
    // underlying tokens. `to` is baked into each commitment, and the AMM itself is the `completer` (the only
    // party allowed to complete them in the public step). no on-behalf-of `from`: you can never nullify
    // another account's private notes.
    #[external("private")]
    fn remove_liquidity(
        to: AztecAddress,
        shares: u128,
        amount0_min: u128,
        amount1_min: u128,
        authwit_nonce: Field,
    ) {
        // --- PRIVATE --- //
        let from = self.msg_sender();

        // sanity checks
        assert(shares > 0 as u128, "shares must be > 0");
        assert((amount0_min > 0 as u128) & (amount1_min > 0 as u128), "amounts must be > 0");

        let config = self.storage.config.read();
        let token0 = Token::at(config.token0);
        let token1 = Token::at(config.token1);
        let lp_token = LiquidityToken::at(self.storage.lp_token.read());

        // move the LP shares from the user's private balance to the pair's public balance,
        // so the public step can burn them against a known total supply. the AMM is the caller
        // here, so `from` must authorize it via authwit_nonce (same as the token pulls in add).
        self.call(lp_token.transfer_private_to_public(from, self.address, shares, authwit_nonce));

        // payouts aren't known privately -> store one partial note (commitment) per token,
        // completer = the AMM, recipient = `to`. public fills the amounts in later.
        let token0_amount_commitment =
            self.call(token0.initialize_transfer_commitment(to, self.address));
        let token1_amount_commitment =
            self.call(token1.initialize_transfer_commitment(to, self.address));

        self.enqueue_self._remove_liquidity(
            token0_amount_commitment,
            token1_amount_commitment,
            shares,
            amount0_min,
            amount1_min,
        );
    }

    // compute each token payout proportional to the redeemed shares: amount = shares * reserve / totalSupply.
    // totalSupply is read BEFORE the burn, so the denominator still includes the shares being redeemed
    // (the correct proportion). because shares <= totalSupply, each payout <= its reserve, so the reserve
    // subtraction can't underflow. mul_div floors, which favors the pool (user gets <= exact share).
    //
    // payouts are delivered by completing the commitments stored in the private step:
    // transfer_public_to_commitment moves tokens from the pair's public balance into the partial note,
    // and `to` (sealed into the commitment) receives them as private notes.
    // finally we burn the shares the pair is now holding.
    #[only_self]
    #[external("public")]
    fn _remove_liquidity(
        token0_amount_commitment: Field,
        token1_amount_commitment: Field,
        shares: u128,
        amount0_min: u128,
        amount1_min: u128,
    ) {
        let config = self.storage.config.read();
        let token0 = Token::at(config.token0);
        let token1 = Token::at(config.token1);
        let lp_token = LiquidityToken::at(self.storage.lp_token.read());

        // proportional payout from current reserves (supply read before the burn)
        let reserve0 = self.storage.reserve0.read();
        let reserve1 = self.storage.reserve1.read();
        let lp_token_total_supply = self.view(lp_token.total_supply());

        let token0_amount = mul_div(shares, reserve0, lp_token_total_supply);
        let token1_amount = mul_div(shares, reserve1, lp_token_total_supply);

        // slippage protection
        assert(token0_amount >= amount0_min, "amount0 to return is less than minimum");
        assert(token1_amount >= amount1_min, "amount1 to return is less than minimum");

        // decrement reserves to stay in sync with the public balance we're about to pay out
        self.storage.reserve0.write(reserve0 - token0_amount);
        self.storage.reserve1.write(reserve1 - token1_amount);

        // pay out: public balance -> commitment (partial note); `to` (sealed in the commitment) gets private notes
        self.call(token0.transfer_public_to_commitment(
            self.address,
            token0_amount_commitment,
            token0_amount,
            0,
        ));
        self.call(token1.transfer_public_to_commitment(
            self.address,
            token1_amount_commitment,
            token1_amount,
            0,
        ));
        // burn the shares the pair is now holding publicly
        self.call(lp_token.burn_from_public(self.address, shares, 0));
        self.emit(
            LiquidityRemoved { amount0: token0_amount, amount1: token1_amount, shares: shares },
        );
    }

    // private swap (exact input): the caller spends `amount_in` of `token_in` and receives
    // at least `amount_out_min` of the other token as a private note.
    //
    // same two-step / partial-note pattern as add/remove: reserves are public, so the price
    // can't be known privately. the private part moves the input into the pool's public balance
    // and leaves ONE output commitment; the public part reads reserves, prices it via
    // get_amount_out, and completes the commitment.
    //
    // direction is decided once here (`zero_for_one`) and handed to public, so public never
    // re-validates the token - it only uses the bool to index reserves. exact-input means the
    // whole input is consumed, so there is no input refund.
    //
    // the caller funds the swap (their private notes are spent); `to` receives the output notes.
    // no on-behalf-of `from`: you can never nullify another account's private notes.
    #[external("private")]
    fn swap(
        to: AztecAddress,
        token_in: AztecAddress,
        amount_in: u128,
        amount_out_min: u128,
        transfer_nonce: Field,
    ) {
        // --- PRIVATE --- //
        let from = self.msg_sender();

        // sanity checks
        assert(amount_in > 0 as u128, "amount_in must be > 0");
        assert(amount_out_min > 0 as u128, "amount_out_min must be > 0");

        let config = self.storage.config.read();

        // decide direction once; `token_in` stays an AztecAddress throughout
        let zero_for_one = token_in.eq(config.token0);
        assert(
            zero_for_one | token_in.eq(config.token1),
            "token_in must be either token0 or token1",
        );
        let token_out_address = if zero_for_one {
            config.token1
        } else {
            config.token0
        };

        // pull the exact input from the caller's private balance into the pool's public balance
        self.call(Token::at(token_in).transfer_private_to_public(
            from,
            self.address,
            amount_in,
            transfer_nonce,
        ));

        // partial note for the output; amount is filled in publicly once reserves are known
        let token_out_commitment = self.call(Token::at(token_out_address)
            .initialize_transfer_commitment(to, self.address));

        self.enqueue_self._swap(token_out_commitment, amount_in, amount_out_min, zero_for_one);
    }

    // price the swap against current reserves and complete the output commitment.
    // `zero_for_one` (trusted: only_self) selects which reserve is in vs out and which token
    // pays out. get_amount_out < reserve_out always holds for the CPMM formula, so the
    // reserve_out subtraction can't underflow.
    #[only_self]
    #[external("public")]
    fn _swap(
        token_out_commitment: Field,
        amount_in: u128,
        amount_out_min: u128,
        zero_for_one: bool,
    ) {
        // reserves are public -> read fresh here; the bool routes which slot is in vs out
        let reserve_in = if zero_for_one {
            self.storage.reserve0.read()
        } else {
            self.storage.reserve1.read()
        };
        let reserve_out = if zero_for_one {
            self.storage.reserve1.read()
        } else {
            self.storage.reserve0.read()
        };

        // price the swap net of fee, then enforce the caller's slippage bound
        let amount_out = get_amount_out(
            amount_in,
            reserve_in,
            reserve_out,
            self.storage.fee_rate.read(),
        );
        assert(amount_out >= amount_out_min, "amount_out is less than minimum");

        // settle reserves: input side grows by the full input, output side shrinks by the payout.
        // the branch maps the in/out roles back to the 0/1 slot identity.
        if zero_for_one {
            self.storage.reserve0.write(reserve_in + amount_in);
            self.storage.reserve1.write(reserve_out - amount_out);
        } else {
            self.storage.reserve1.write(reserve_in + amount_in);
            self.storage.reserve0.write(reserve_out - amount_out);
        };

        // pay the output: move it from the pool's public balance into the partial note opened in
        // private; `to` (sealed into the commitment) receives it as a private note.
        let config = self.storage.config.read();
        let token_out = Token::at(
            if zero_for_one {
                config.token1
            } else {
                config.token0
            },
        );
        self.call(token_out.transfer_public_to_commitment(
            self.address,
            token_out_commitment,
            amount_out,
            0,
        ));

        self.emit(Swapped { amount_in, amount_out, zero_for_one });
    }

    // ----- getters ----- //
    // ------------------- //
    #[external("public")]
    #[view]
    fn token0() -> AztecAddress {
        self.storage.config.read().token0
    }

    #[external("public")]
    #[view]
    fn token1() -> AztecAddress {
        self.storage.config.read().token1
    }

    #[external("public")]
    #[view]
    fn lp_token_address() -> AztecAddress {
        self.storage.lp_token.read()
    }

    #[external("public")]
    #[view]
    fn reserve0() -> u128 {
        self.storage.reserve0.read()
    }

    #[external("public")]
    #[view]
    fn reserve1() -> u128 {
        self.storage.reserve1.read()
    }

    #[external("public")]
    #[view]
    fn fee_rate() -> u32 {
        self.storage.fee_rate.read()
    }

}
