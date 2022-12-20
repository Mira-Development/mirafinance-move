module mira::coins {
    use std::signer::address_of;

    use aptos_framework::managed_coin::{Self, register};

    const UNIT_DECIMAL: u64 = 100000000;

    struct APT {}
    struct USDC {}
    struct BTC {}
    struct ETH {}
    struct SOL {}

    public fun init_local_coins(sender: &signer) {
        managed_coin::initialize<APT>(sender, b"Aptos", b"APT", 8, true);
        managed_coin::initialize<USDC>(sender, b"USD Coin", b"USDC", 8, true);
        managed_coin::initialize<BTC>(sender, b"Bitcoin", b"BTC", 8, true);
        managed_coin::initialize<ETH>(sender, b"Ethereum", b"ETH", 8, true);
        managed_coin::initialize<SOL>(sender, b"Solana", b"SOL", 8, true);

        register<APT>(sender);
        register<USDC>(sender);
        register<BTC>(sender);
        register<ETH>(sender);
        register<SOL>(sender);
    }

    public fun mint(sender: &signer){
        managed_coin::mint<APT>(sender, address_of(sender), 15000 * UNIT_DECIMAL);
        managed_coin::mint<USDC>(sender, address_of(sender), 150000 * UNIT_DECIMAL);
        managed_coin::mint<BTC>(sender, address_of(sender), 10 * UNIT_DECIMAL);
        managed_coin::mint<ETH>(sender, address_of(sender), 150 * UNIT_DECIMAL );
        managed_coin::mint<SOL>(sender, address_of(sender), 7500 * UNIT_DECIMAL);
    }
}