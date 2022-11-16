#[test_only]
module mira::test1 {
    use mira::mira;
    use std::signer::address_of;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use mira::coins::{USDC, BTC, ETH, SOL, APT};
    // use mira::mira::{print_real_pool_distribution, print_pool_info, print_investor_stakes};
    use mira::coins;
    // use std::string;
    use std::vector;
    use mira::mira::{print_investor_stakes, print_account_info, send_funds_to_user};

    const UNIT_DECIMAL: u64 = 100000000;

    // struct AptosCoinTest has key {
    //     mint_cap: MintCapability<AptosCoin>,
    //     burn_cap: BurnCapability<AptosCoin>
    // }

    #[test (bank = @0xbb171011e3d8fb5af1991c6a5d8107c28702db906d9f03e732777800872fec52,
        admin = @mira, alice = @0x222, bob = @0x333, carl = @0x444, daisy = @0x555)]
        public entry fun run_all_tests(
        bank: &signer,
        admin: &signer,
        alice: &signer,
        bob: &signer,
        carl: &signer,
        daisy: &signer
    ) {
        let bank_addr = address_of(bank);
        // account::create_account_for_test(bank_addr);
        coins::init_local_coins(bank);

        let admin_addr = address_of(admin);
        account::create_account_for_test(admin_addr);
        mira::init_mira(admin);

        let alice_acct = address_of(alice);
        account::create_account_for_test(alice_acct);
        mira::connect_account(alice, b"Alice");

        let bob_acct = address_of(bob);
        account::create_account_for_test(bob_acct);
        mira::connect_account(bob, b"Bob");

        let carl_acct = address_of(carl);
        account::create_account_for_test(carl_acct);
        mira::connect_account(carl, b"Carl");

        let daisy_acct = address_of(daisy);
        account::create_account_for_test(daisy_acct);
        mira::connect_account(daisy, b"Daisy");

        // let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        // let minted_aptos = coin::mint<AptosCoin>(10000 * UNIT_DECIMAL, &mint_cap);

        // coin::deposit<AptosCoin>(bank_addr, minted_aptos);

        // move_to(bank, AptosCoinTest {
        //     mint_cap,
        //     burn_cap
        // });

        // register coins
        managed_coin::register<APT>(bank);
        managed_coin::register<USDC>(bank);
        managed_coin::register<BTC>(bank);
        managed_coin::register<ETH>(bank);
        managed_coin::register<SOL>(bank);

        // mint coins, total supply of 75,000 APT w/ rough exchange rates
        managed_coin::mint<APT>(bank, bank_addr, 15000 * UNIT_DECIMAL);
        managed_coin::mint<USDC>(bank, bank_addr, 150000 * UNIT_DECIMAL);
        managed_coin::mint<BTC>(bank, bank_addr, 10 * UNIT_DECIMAL);
        managed_coin::mint<ETH>(bank, bank_addr, 150 * UNIT_DECIMAL );
        managed_coin::mint<SOL>(bank, bank_addr, 7500 * UNIT_DECIMAL);

        coin::transfer<APT>(bank, alice_acct, 100 * UNIT_DECIMAL);
        coin::transfer<BTC>(bank, alice_acct, 1 * UNIT_DECIMAL);
        coin::transfer<APT>(bank, bob_acct, 2 * UNIT_DECIMAL);
        coin::transfer<APT>(bank, carl_acct, 10 * UNIT_DECIMAL);
        coin::transfer<BTC>(bank, daisy_acct, 2 * UNIT_DECIMAL);
        coin::transfer<APT>(bank, daisy_acct, 20 * UNIT_DECIMAL);

        create_simple_pool(alice, 1005 * UNIT_DECIMAL/100, 4 * UNIT_DECIMAL); // alice deposits 10.05 APT in simple portfolio, fee @ 4%
        create_btc_pool(alice, 1 * UNIT_DECIMAL, 10 * UNIT_DECIMAL); // alice deposits 1 BTC in btc portfolio, fee @ 1%
        btc_invest(daisy, alice_acct, 2 * UNIT_DECIMAL); // daisy invests 2 BTC in btc portfolio
        //btc_withdraw(daisy, alice_acct, 2 * UNIT_DECIMAL); // daisy withdraws max amount, TODO: fix can't withdraw in BTC bc of table issue
        update_simple_pool(alice, 2125 * UNIT_DECIMAL/1000); // alice updates fee to 2.125%, allocation, rebalancing, and rebalance_on_investment

        change_gas_funds(alice, 5 * UNIT_DECIMAL / 100, 1); // remove 0.05 APT from gas funds
        change_gas_funds(alice, 20 * UNIT_DECIMAL / 100, 0); // add 0.20 APT to gas funds

        manager_rebalance(alice);

        simple_invest(bob, alice_acct, 1 * UNIT_DECIMAL); // bob invests 1 APT in alice's pool worth 10 APT, giving him 8.8% stake after fees
        simple_invest(bob, alice_acct, 1 * UNIT_DECIMAL); // bob invests another 1 APT in alice's pool worth 11 APT, giving him 16.2% stake after fees
        simple_invest(carl, alice_acct, 10 * UNIT_DECIMAL); // carl invests 10 APT in alice's pool worth 12 APT
        simple_invest(daisy, alice_acct, 20 * UNIT_DECIMAL); // daisy invests 20 APT in alice's pool worth 22 APT
        simple_invest(alice, alice_acct, 5 * UNIT_DECIMAL); // alice invests 5 more APT in her own pool worth 42 APT
        print_investor_stakes(alice_acct, b"simple_portfolio");


        simple_withdraw(bob, alice_acct, 1 * UNIT_DECIMAL); // bob has 1.9575 to withdraw
        simple_withdraw(bob, alice_acct, 9 * UNIT_DECIMAL/10);
        simple_withdraw(bob, alice_acct, 5 * UNIT_DECIMAL/100);
        simple_withdraw(bob, alice_acct, 7 * UNIT_DECIMAL/1000);
        simple_withdraw(bob, alice_acct, 5 * UNIT_DECIMAL/10000); // rounding error causes some issues here
        mira::lock_withdrawals(admin);
        mira::unlock_withdrawals(admin);
        simple_withdraw(carl, alice_acct, 100 * UNIT_DECIMAL);
        simple_withdraw(alice, alice_acct, 100 * UNIT_DECIMAL);
        print_investor_stakes(alice_acct, b"simple_portfolio");
        // simple_withdraw(daisy, alice_acct, 100 * UNIT_DECIMAL); TODO: fix last stakeholder can't withdraw everything

        send_funds_to_user<APT>(alice, daisy_acct, 10 * UNIT_DECIMAL);
        print_account_info(daisy);
    }

    public entry fun create_simple_pool(manager: &signer, amount: u64, management_fee: u64){
        let simple_tokens = vector::empty<vector<u8>>();
        vector::push_back(&mut simple_tokens, b"BTC");
        vector::push_back(&mut simple_tokens, b"ETH");

        let simple_allocation = vector::empty<u64>();
        vector::push_back(&mut simple_allocation, 50);
        vector::push_back(&mut simple_allocation, 50);

        mira::create_pool<APT>(manager,
            b"simple_portfolio",
            simple_tokens,
            simple_allocation,
            amount, // $APT 1.00000000
            management_fee, // 2.125000000%
            0,
            10, // in days (0 - 730)
            0
        );
        // print_pool_info(manager, b"simple_portfolio");
        // print_real_pool_distribution(address_of(manager), string::utf8(b"simple_portfolio"));
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

        mira::update_pool(manager, b"simple_portfolio", update_tokens, update_allocation,
            management_fee, 5, 1);

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

        mira::create_pool<BTC>(manager,
            b"btc_portfolio",
            simple_tokens,
            simple_allocation,
            amount, // $APT 1.00000000
            management_fee, // 2.125000000%
            0,
            10, // in days (0 - 730)
            0
        );

        // print_pool_info(manager, b"btc_portfolio");
        // print_real_pool_distribution(address_of(manager), string::utf8(b"btc_portfolio"));
    }

    public entry fun manager_rebalance(manager: &signer){
        mira::rebalance(manager, address_of(manager), b"simple_portfolio");
        // print_pool_info(manager, b"simple_portfolio");
    }

    public entry fun change_gas_funds(manager: &signer, amount: u64, add_or_remove: u8){
        mira::change_gas_funds(manager, b"simple_portfolio", amount, add_or_remove);
    }

    public entry fun simple_invest(investor: &signer, pool_owner: address, amount: u64){
        mira::invest<APT>(investor, b"simple_portfolio", pool_owner, amount);
        // print_investor_stakes(pool_owner, b"simple_portfolio");
    }

    public entry fun btc_invest(investor: &signer, pool_owner: address, amount: u64){
        mira::invest<BTC>(investor, b"btc_portfolio", pool_owner, amount);
        // print_investor_stakes(pool_owner, b"btc_portfolio");
    }

    public entry fun simple_withdraw(investor: &signer, manager: address, amount: u64){
        mira::withdraw<APT>(investor, b"simple_portfolio", manager, amount);
    }

    public entry fun btc_withdraw(investor: &signer, manager: address, amount: u64){
        mira::withdraw<BTC>(investor, b"simple_portfolio", manager, amount);
    }
}
