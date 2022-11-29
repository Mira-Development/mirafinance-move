#[test_only]
module mira::liquid_test {
    use mira::mira;
    use std::signer::address_of;
    use aptos_framework::account;
    use aptos_framework::coin;
    use std::vector;
    use std::option;
    use std::option::some;
    use aptos_framework::genesis;
    use liquidswap::lp_account;
    use liquidswap::liquidity_pool;
    use aptos_framework::coin::{Coin, register};
    use liquidswap_lp::lp_coin::LP;
    use liquidswap::curves::Uncorrelated;
    use mira::better_coins::{BTC, USDC, SOL, mint, add_coins_to_admin, APT, ETH};
    use mira::mira::{ print_real_pool_distribution};
    use std::string;
    use mira::oracle::init_oracle;
    use aptos_framework::timestamp;
    use aptos_framework::timestamp::{set_time_has_started_for_testing};

    const UNIT_DECIMAL: u64 = 100000000;

    #[test (admin = @mira, alice = @0x222, bob = @0x333, carl = @0x444, dalya = @0x555)]
        public entry fun run_all_tests(
        admin: &signer,
        alice: &signer,
        bob: &signer,
        carl: &signer,
        dalya: &signer,
    ) {

        genesis::setup(); //?
        set_time_has_started_for_testing(admin);
        timestamp::fast_forward_seconds(100000);

        account::create_account_for_test(address_of(admin));
        mint_helper(admin);

        mira::init_mira(admin);
        timestamp::fast_forward_seconds(100000);

        let alice_acct = address_of(alice);
        account::create_account_for_test(alice_acct);
        mira::connect_account(alice, b"Alice");

        let bob_acct = address_of(bob);
        account::create_account_for_test(bob_acct);
        mira::connect_account(bob, b"Bob");

        let carl_acct = address_of(carl);
        account::create_account_for_test(carl_acct);
        mira::connect_account(carl, b"Carl");

        let daisy_acct = address_of(dalya);
        account::create_account_for_test(daisy_acct);
        mira::connect_account(dalya, b"Daisy");

        coin::transfer<USDC>(admin, alice_acct, 100 * UNIT_DECIMAL);
        coin::transfer<USDC>(admin, bob_acct, 2 * UNIT_DECIMAL);
        coin::transfer<USDC>(admin, carl_acct, 10 * UNIT_DECIMAL);
        coin::transfer<USDC>(admin, daisy_acct, 20 * UNIT_DECIMAL);
        coin::transfer<BTC>(admin, daisy_acct, 2 * UNIT_DECIMAL);

        timestamp::fast_forward_seconds(100000);
        create_simple_pool(alice, 1005 * UNIT_DECIMAL/100, 4 * UNIT_DECIMAL); // alice deposits 10.05 USD in simple portfolio, fee @ 4%
    }

    public entry fun create_simple_pool(manager: &signer, amount: u64, management_fee: u64){
        let simple_tokens = vector::empty<vector<u8>>();
        vector::push_back(&mut simple_tokens, b"BTC");
        vector::push_back(&mut simple_tokens, b"ETH");

        let simple_allocation = vector::empty<u64>();
        vector::push_back(&mut simple_allocation, 50);
        vector::push_back(&mut simple_allocation, 50);

        mira::create_pool<USDC>(manager,
            b"simple_portfolio",
            simple_tokens,
            simple_allocation,
            amount, // $APT 1.00000000
            management_fee, // 2.125000000%
            0,
            10, // in days (0 - 730)
            0,
            option::none()
        );
        //print_pool_info(manager, b"simple_portfolio");
        print_real_pool_distribution(address_of(manager), string::utf8(b"simple_portfolio"));
    }

    public entry fun update_simple_pool(manager: &signer, management_fee: u64){
        let update_tokens = vector::empty<vector<u8>>();
        vector::push_back(&mut update_tokens, b"APT");
        vector::push_back(&mut update_tokens, b"USDC");
        vector::push_back(&mut update_tokens, b"BTC");
        vector::push_back(&mut update_tokens, b"SOL");

        let update_allocation = vector::empty<u64>();
        vector::push_back(&mut update_allocation, 25);
        vector::push_back(&mut update_allocation, 20);
        vector::push_back(&mut update_allocation, 25);
        vector::push_back(&mut update_allocation, 30);

        mira::update_pool(manager, b"simple_portfolio", some(update_tokens), some(update_allocation),
            some(management_fee), some(5), some(1), option::none(), 0);

        // print_pool_info(manager, b"simple_portfolio");
        // print_investor_stakes(address_of(manager), b"simple_portfolio")
    }

    public entry fun create_btc_pool(manager: &signer, amount: u64, management_fee: u64){
        mira::connect_account(manager, b"Alice");

        let simple_tokens = vector::empty<vector<u8>>();
        vector::push_back(&mut simple_tokens, b"BTC");
        vector::push_back(&mut simple_tokens, b"ETH");

        let simple_allocation = vector::empty<u64>();
        vector::push_back(&mut simple_allocation, 50);
        vector::push_back(&mut simple_allocation, 50);

        mira::create_pool<mira::coins::BTC>(manager,
            b"btc_portfolio",
            simple_tokens,
            simple_allocation,
            amount, // $APT 1.00000000
            management_fee, // 2.125000000%
            0,
            10, // in days (0 - 730)
            0,
            option::none()
        );

        // print_pool_info(manager, b"btc_portfolio");
        // print_real_pool_distribution(address_of(manager), string::utf8(b"btc_portfolio"));
    }

    public entry fun manager_rebalance(manager: &signer){
        mira::rebalance<APT>(manager, address_of(manager), b"simple_portfolio");
        // print_pool_info(manager, b"simple_portfolio");
    }

    public entry fun change_gas_funds(manager: &signer, amount: u64, add_or_remove: u8){
        mira::change_gas_funds(manager, b"simple_portfolio", amount, add_or_remove);
    }

    public entry fun simple_invest(investor: &signer, pool_owner: address, amount: u64){
        mira::invest<mira::coins::APT>(investor, b"simple_portfolio", pool_owner, amount);
        // print_investor_stakes(pool_owner, b"simple_portfolio");
    }

    public entry fun btc_invest(investor: &signer, pool_owner: address, amount: u64){
        mira::invest<mira::coins::BTC>(investor, b"btc_portfolio", pool_owner, amount);
        // print_investor_stakes(pool_owner, b"btc_portfolio");
    }

    public entry fun simple_withdraw(investor: &signer, manager: address, amount: u64){
        mira::withdraw<mira::coins::APT>(investor, b"simple_portfolio", manager, amount, 0);
    }

    public entry fun btc_withdraw(investor: &signer, manager: address, amount: u64){
        mira::withdraw<mira::coins::BTC>(investor, b"btc_portfolio", manager, amount, 0);
    }

    public entry fun lock_and_unlock(admin: &signer){
        mira::lock_withdrawals(admin);
        mira::unlock_withdrawals(admin);
    }

    public entry fun yearly_management(signer: &signer, manager: address, pool_name: vector<u8>){
        mira::yearly_management(signer, manager, pool_name);
    }

    public entry fun update_management_fee(admin: &signer, fee: u64){
        mira::update_management_fee(admin, fee);
    }

    // LIQUIDSWAP ______________________________________________________________________________________________________

    public fun create_lp_owner(): signer {
        let pool_owner = account::create_account_for_test(@test_lp_owner);
        pool_owner
    }

    public fun create_liquidswap_admin(): signer {
        let admin = account::create_account_for_test(@liquidswap);
        admin
    }

    public fun initialize_liquidity_pool() {
        let liquidswap_admin = account::create_account_for_test(@liquidswap);
        let lp_coin_metadata = x"064c50436f696e010000000000000000403239383333374145433830334331323945313337414344443138463135393936323344464146453735324143373738443344354437453231454133443142454389021f8b08000000000002ff2d90c16ec3201044ef7c45e44b4eb13160c0957aeab5952af51845d1b22c8995c45860bbfdfce2b4b79dd59b9dd11e27c01b5ce8c44678d0ee75b77fff7c8bc3b8672ba53cc4715bb535aff99eb123789f2867ca27769fce58b83320c6659c0b56f19f36980e21f4beb5207a05c48d54285b4784ad7306a5e8831460add6ce486dc98014aed78e2b521d5525c3d37af034d1e869c48172fd1157fa9afd7d702776199e49d7799ef24bd314795d5c8df1d1c034c77cb883cbff23c64475012a9668dd4c3668a91c7a41caa2ea8db0da7ace3be965274550c1680ed4f615cb8bf343da3c7fa71ea541135279d0774cb7669387fc6c54b15fb48937414101000001076c705f636f696e5c1f8b08000000000002ff35c8b10980301046e13e53fc0338411027b0b0d42a84535048ee82de5521bb6b615ef5f8b2ec960ea412482e0e91488cd5fb1f501dbe1ebd8d14f3329633b24ac63aa0ef36a136d7dc0b3946fd604b00000000000000";
        let lp_coin_code = x"a11ceb0b050000000501000202020a070c170823200a4305000000010003000100010001076c705f636f696e024c500b64756d6d795f6669656c6435e1873b2a1ae8c609598114c527b57d31ff5274f646ea3ff6ecad86c56d2cf8000201020100";

        lp_account::initialize_lp_account(
            &liquidswap_admin,
            lp_coin_metadata,
            lp_coin_code
        );
        // retrieves SignerCapability
        liquidity_pool::initialize(&liquidswap_admin);
    }

    public fun setup_lp_owner(): signer {
        initialize_liquidity_pool();

        let lp_owner = create_lp_owner();
        lp_owner
    }

    public fun mint_liquidity<X, Y, Curve>(lp_owner: &signer, coin_x: Coin<X>, coin_y: Coin<Y>): u64 {
        init_oracle<X, Y, Curve>(lp_owner);
        timestamp::fast_forward_seconds(100000);
        let lp_owner_addr = address_of(lp_owner);
        let lp_coins = liquidity_pool::mint<X, Y, Curve>(coin_x, coin_y);
        let lp_coins_val = coin::value(&lp_coins);
        if (!coin::is_account_registered<LP<X, Y, Curve>>(lp_owner_addr)) {
            coin::register<LP<X, Y, Curve>>(lp_owner);
        };
        coin::deposit(lp_owner_addr, lp_coins);
        lp_coins_val
    }

    fun setup_pools(): signer {
        let lp_owner = setup_lp_owner();

        liquidity_pool::register<APT, USDC, Uncorrelated>(&lp_owner);

        liquidity_pool::register<APT, BTC, Uncorrelated>(&lp_owner);

        liquidity_pool::register<APT, ETH, Uncorrelated>(&lp_owner);

        liquidity_pool::register<APT, SOL, Uncorrelated>(&lp_owner);
        lp_owner
    }

    fun mint_helper(coin_admin: &signer){
        add_coins_to_admin(coin_admin);

        let lp_owner = setup_pools();
        let bank = address_of(coin_admin);

        mint_liquidity<APT, USDC, Uncorrelated>(&lp_owner, mint<APT>(coin_admin, 1000 * UNIT_DECIMAL),
            mint<USDC>(coin_admin, 10000 * UNIT_DECIMAL));
        mint_liquidity<APT, BTC, Uncorrelated>(&lp_owner, mint<APT>(coin_admin, 10000 * UNIT_DECIMAL),
            mint<BTC>(coin_admin, 10 * UNIT_DECIMAL));
        mint_liquidity<APT, ETH, Uncorrelated>(&lp_owner, mint<APT>(coin_admin, 1000 * UNIT_DECIMAL),
            mint<ETH>(coin_admin, 100 * UNIT_DECIMAL));
        mint_liquidity<APT, SOL, Uncorrelated>(&lp_owner, mint<APT>(coin_admin, 1000 * UNIT_DECIMAL),
            mint<SOL>(coin_admin, 500 * UNIT_DECIMAL));

        // mint for bank:
        register<APT>(coin_admin);
        register<USDC>(coin_admin);
        register<BTC>(coin_admin);
        register<ETH>(coin_admin);
        register<SOL>(coin_admin);

        coin::deposit(bank, mint<APT>(coin_admin, 15000 * UNIT_DECIMAL));
        coin::deposit(bank,mint<USDC>(coin_admin, 150000 * UNIT_DECIMAL));
        coin::deposit(bank,mint<BTC>(coin_admin, 10 * UNIT_DECIMAL));
        coin::deposit(bank,mint<ETH>(coin_admin, 150 * UNIT_DECIMAL));
        coin::deposit(bank,mint<SOL>(coin_admin, 7500 * UNIT_DECIMAL));
    }

}

