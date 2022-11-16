module mira::coins {
    use aptos_framework::managed_coin;

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
    }

}
