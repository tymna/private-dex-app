use aztec::macros::aztec;

#[aztec]
pub contract LiquidityToken {
    use aztec::{
        macros::{
            functions::{authorize_once, external, initializer, internal, only_self, view},
            storage::storage,
        },
        protocol::{address::AztecAddress, traits::{FromField, ToField}},
        state_vars::{Map, Owned, PublicImmutable, PublicMutable, StateVariable},
    };
    use aztec::messages::message_delivery::MessageDelivery;
    use balance_set::BalanceSet;
    use compressed_string::FieldCompressedString;
    use uint_note::{PartialUintNote, UintNote};

    global INITIAL_TRANSFER_MAX_NOTES: u32 = 2;
    global RECURSIVE_TRANSFER_MAX_NOTES: u32 = 8;

    #[storage]
    struct Storage<Context> {
        name: PublicImmutable<FieldCompressedString, Context>,
        symbol: PublicImmutable<FieldCompressedString, Context>,
        decimals: PublicImmutable<u8, Context>,
        minter: PublicImmutable<AztecAddress, Context>,
        total_supply: PublicMutable<u128, Context>,
        public_balances: Map<AztecAddress, PublicMutable<u128, Context>, Context>,
        private_balances: Owned<BalanceSet<Context>, Context>,
    }

    // ----- constructor ----- //
    #[external("public")]
    #[initializer]
    fn constructor(name: str<31>, symbol: str<31>, decimals: u8, minter: AztecAddress) {
        self.storage.name.initialize(FieldCompressedString::from_string(name));
        self.storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        self.storage.decimals.initialize(decimals);
        self.storage.minter.initialize(minter);
    }

    // ----- public external ----- //
    #[external("public")]
    fn mint_public_to_commitment(commitment: Field, amount: u128) {
        let completer = self.msg_sender();
        _validate_minter(completer, self.storage.minter.read());
        self.internal._increase_total_supply(amount);
        self.internal._increase_commitment_balance(
            PartialUintNote::from_field(commitment),
            completer,
            amount,
        );
    }

    #[external("public")]
    fn mint_to_public(to: AztecAddress, amount: u128) {
        _validate_minter(self.msg_sender(), self.storage.minter.read());
        self.internal._increase_total_supply(amount);
        let new_balance = self.storage.public_balances.at(to).read() + amount;
        self.storage.public_balances.at(to).write(new_balance);
    }

    #[authorize_once("from", "_nonce")]
    #[external("public")]
    fn burn_from_public(from: AztecAddress, amount: u128, _nonce: Field) {
        self.internal._decrease_public_balance(from, amount);
        self.internal._decrease_total_supply(amount);
    }

    // ----- public internal wrappers ----- //
    #[external("public")]
    #[only_self]
    fn increase_total_supply_internal(amount: u128) {
        self.internal._increase_total_supply(amount);
    }

    #[external("public")]
    #[only_self]
    fn decrease_total_supply_internal(amount: u128) {
        self.internal._decrease_total_supply(amount);
    }

    #[external("public")]
    #[only_self]
    fn increase_public_balance_internal(to: AztecAddress, amount: u128) {
        self.internal._increase_public_balance(to, amount);
    }

    // ----- public internal ----- //
    #[internal("public")]
    fn _increase_total_supply(amount: u128) {
        let new_total_supply = self.storage.total_supply.read() + amount;
        self.storage.total_supply.write(new_total_supply);
    }

    #[internal("public")]
    fn _decrease_total_supply(amount: u128) {
        let supply = self.storage.total_supply.read();
        assert(supply >= amount, "Underflow");
        self.storage.total_supply.write(supply - amount);
    }

    #[internal("public")]
    fn _increase_public_balance(to: AztecAddress, amount: u128) {
        let new_balance = self.storage.public_balances.at(to).read() + amount;
        self.storage.public_balances.at(to).write(new_balance);
    }

    #[internal("public")]
    fn _decrease_public_balance(from: AztecAddress, amount: u128) {
        let new_balance = self.storage.public_balances.at(from).read() - amount;
        self.storage.public_balances.at(from).write(new_balance);
    }

    #[internal("public")]
    fn _increase_commitment_balance(
        commitment: PartialUintNote,
        completer: AztecAddress,
        amount: u128,
    ) {
        commitment.complete(
            self.context,
            completer,
            self.storage.private_balances.get_storage_slot(),
            amount,
        );
    }

    // ----- private external ----- //
    #[external("private")]
    fn mint_to_private(to: AztecAddress, amount: u128) {
        assert(self.storage.minter.read().eq(self.msg_sender()), "Caller is not minter");
        self.internal._increase_private_balance(to, amount);
        self.enqueue_self.increase_total_supply_internal(amount);
    }

    #[external("private")]
    fn burn_from_private(from: AztecAddress, amount: u128) {
        assert(self.storage.minter.read().eq(self.msg_sender()), "Caller is not minter");
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_MAX_NOTES);
        self.enqueue_self.decrease_total_supply_internal(amount);
    }

    #[authorize_once("from", "authwit_nonce")]
    #[external("private")]
    fn transfer_private_to_private(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        authwit_nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_MAX_NOTES);
        self.internal._increase_private_balance(to, amount);
    }

    #[authorize_once("from", "_nonce")]
    #[external("private")]
    fn transfer_private_to_public(
        from: AztecAddress,
        to: AztecAddress,
        amount: u128,
        _nonce: Field,
    ) {
        self.internal._decrease_private_balance(from, amount, INITIAL_TRANSFER_MAX_NOTES);
        self.enqueue_self.increase_public_balance_internal(to, amount);
    }

    #[external("private")]
    fn recurse_substract_balance_internal(from: AztecAddress, amount: u128) -> u128 {
        self.internal._substract_balance(from, amount, RECURSIVE_TRANSFER_MAX_NOTES);
    }

    #[external("private")]
    fn initialize_transfer_commitment(to: AztecAddress, completer: AztecAddress) -> Field {
        let commitment = self.internal._initialize_transfer_commitment(to, completer);
        commitment.to_field()
    }

    // ----- private internal ----- //
    #[internal("private")]
    fn _increase_private_balance(to: AztecAddress, amount: u128) {
        self.storage.private_balances.at(to).add(amount).deliver(MessageDelivery.ONCHAIN_CONSTRAINED);
    }

    #[internal("private")]
    fn _decrease_private_balance(from: AztecAddress, amount: u128, max_notes: u32) {
        let change = self.internal._substract_balance(from, amount, max_notes);
        self.storage.private_balances.at(from).add(change).deliver(
            MessageDelivery.ONCHAIN_CONSTRAINED,
        );
    }

    #[internal("private")]
    fn _substract_balance(from: AztecAddress, amount: u128, max_notes: u32) -> u128 {
        let consumed_amount = self.storage.private_balances.at(from).try_sub(amount, max_notes);

        if consumed_amount >= amount {
            consumed_amount - amount
        } else {
            assert(consumed_amount > 0, "Balance too low");
            let remaining_amount = amount - consumed_amount;
            self.call_self.recurse_substract_balance_internal(from, remaining_amount)
        }
    }

    #[internal("private")]
    fn _initialize_transfer_commitment(
        to: AztecAddress,
        completer: AztecAddress,
    ) -> PartialUintNote {
        let commitment = UintNote::partial(to, self.context, to, completer);

        commitment
    }

    // ----- getters ----- //
    #[external("public")]
    #[view]
    fn total_supply() -> u128 {
        self.storage.total_supply.read()
    }

    #[external("public")]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> u128 {
        self.storage.public_balances.at(owner).read()
    }

    #[external("public")]
    #[view]
    fn name() -> FieldCompressedString {
        self.storage.name.read()
    }

    #[external("public")]
    #[view]
    fn symbol() -> FieldCompressedString {
        self.storage.symbol.read()
    }

    #[external("public")]
    #[view]
    fn decimals() -> u8 {
        self.storage.decimals.read()
    }

    #[external("public")]
    #[view]
    fn minter() -> AztecAddress {
        self.storage.minter.read()
    }

    #[external("utility")]
    unconstrained fn balance_of_private(owner: AztecAddress) -> u128 {
        self.storage.private_balances.at(owner).balance_of()
    }

    #[contract_library_method]
    fn _validate_minter(sender: AztecAddress, minter: AztecAddress) {
        assert(minter.eq(sender), "caller is not minter");
    }

}
