module mira::better_coins {
    use std::signer;
    use std::string::utf8;

    use aptos_framework::coin::{Self, Coin, MintCapability, BurnCapability};

    struct BTC {}

    struct APT {}

    struct USDC {}

    struct ETH {}

    struct SOL {}

    struct Capabilities<phantom CoinType> has key {
        mint_cap: MintCapability<CoinType>,
        burn_cap: BurnCapability<CoinType>,
    }

    // Register one coin with custom details.
    public fun register_coin<CoinType>(coin_admin: &signer, name: vector<u8>, symbol: vector<u8>, decimals: u8) {
        let (burn_cap, freeze_cap, mint_cap, ) = coin::initialize<CoinType>(
            coin_admin,
            utf8(name),
            utf8(symbol),
            decimals,
            true,
        );
        coin::destroy_freeze_cap(freeze_cap);

        move_to(coin_admin, Capabilities<CoinType> {
            mint_cap,
            burn_cap,
        });
    }

    public fun add_coins_to_admin(coin_admin: &signer) {
        register_coins(coin_admin);
    }

    // Register all known coins in one func.
    public fun register_coins(coin_admin: &signer) {
        let (apt_burn_cap, apt_freeze_cap, apt_mint_cap) =
            coin::initialize<APT>(
                coin_admin,
                utf8(b"APT"),
                utf8(b"APT"),
                6,
                true
            );

        let (btc_burn_cap, btc_freeze_cap, btc_mint_cap) =
            coin::initialize<BTC>(
                coin_admin,
                utf8(b"BTC"),
                utf8(b"BTC"),
                8,
                true
            );

        let (usdc_burn_cap, usdc_freeze_cap, usdc_mint_cap) =
            coin::initialize<USDC>(
                coin_admin,
                utf8(b"USDC"),
                utf8(b"USDC"),
                4,
                true,
            );
        let (eth_burn_cap, eth_freeze_cap, eth_mint_cap) =
            coin::initialize<ETH>(
                coin_admin,
                utf8(b"ETH"),
                utf8(b"ETH"),
                6,
                true
            );

        let (sol_burn_cap, sol_freeze_cap, sol_mint_cap) =
            coin::initialize<SOL>(
                coin_admin,
                utf8(b"SOL"),
                utf8(b"SOL"),
                8,
                true
            );

        move_to(coin_admin, Capabilities<APT> {
            mint_cap: apt_mint_cap,
            burn_cap: apt_burn_cap,
        });

        move_to(coin_admin, Capabilities<BTC> {
            mint_cap: btc_mint_cap,
            burn_cap: btc_burn_cap,
        });

        move_to(coin_admin, Capabilities<USDC> {
            mint_cap: usdc_mint_cap,
            burn_cap: usdc_burn_cap,
        });

        move_to(coin_admin, Capabilities<SOL> {
            mint_cap: sol_mint_cap,
            burn_cap: sol_burn_cap,
        });
         move_to(coin_admin, Capabilities<ETH> {
            mint_cap: eth_mint_cap,
            burn_cap: eth_burn_cap,
        });

        coin::destroy_freeze_cap(apt_freeze_cap);
        coin::destroy_freeze_cap(usdc_freeze_cap);
        coin::destroy_freeze_cap(btc_freeze_cap);
        coin::destroy_freeze_cap(sol_freeze_cap);
        coin::destroy_freeze_cap(eth_freeze_cap);
    }

    public fun mint<CoinType>(coin_admin: &signer, amount: u64): Coin<CoinType> acquires Capabilities {
        let caps = borrow_global<Capabilities<CoinType>>(signer::address_of(coin_admin));
        coin::mint(amount, &caps.mint_cap)
    }

    public fun burn<CoinType>(coin_admin: &signer, coins: Coin<CoinType>) acquires Capabilities {
        if (coin::value(&coins) == 0) {
            coin::destroy_zero(coins);
        } else {
            let caps = borrow_global<Capabilities<CoinType>>(signer::address_of(coin_admin));
            coin::burn(coins, &caps.burn_cap);
        };
    }
}
