module 0x1::LessSimpleMira {
    use std::signer::address_of;
    use aptos_framework::account::{create_resource_account};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::table::Table;
    use aptos_std::table;

    // when a user creates a pool, a resource account is created to manage the pool funds
    // the Pools struct stores the resource accounts (addresses) of a user's created pools
    // to access a pool, let user_pools = borrow_global_mut<Pools>(address_of(useraccount)).pool_accounts ->
    // let specific_pool_resource_account = table::borrow_mut<vector<u8>, address>(user_pool_resources, poolname)
    // view MiraPool: borrow_global_mut<MiraPool>(address_of(specific_pool_resource_account))
    struct Pools has key {
        pool_accounts: Table<vector<u8>, address>,
        length: u64
    }

    struct MiraPool has key, store {
        pool_name: vector<u8>,
        pool_address: address,
        manager: address,
        investors: Table<address, u64>,
        index_allocation: Table<vector<u8>, u64>,
        amount: u64,
        signer_capability: account::SignerCapability,
        settings: MiraPoolSettings
    }

    struct MiraPoolSettings has store, copy, drop {
        management_fee: u8,
        rebalancing_period: u8,
        minimum_contribution: u8,
        minimum_withdrawal: u8,
        referral_reward: u8
    }

    // stores information about Mira Users, must be updated based on info from pools created/invested in.
    // Only field changeable by user is account_name, which is initalized to anonymoususer12345...
    struct MiraAccount has key, store {
        owner: address,
        account_name: vector<u8>,
        total_funds_invested: u8,
        funds_under_management: u8,
        funds_on_gas: u8,
        funds_on_management: u8,
        created_pools: Table<u64, MiraPool>,
        invested_pools: Table<u64, MiraPool>,
    }

    // initalize account with an empty Pools struct; no pools have been created
    public fun init(account: &signer){
        let pools = Pools{
            pool_accounts: table::new<vector<u8>, address>(),
            length: 0
        };
        move_to(account, pools);
    }

    // check if account has already connected to Mira Dapp;
    // if not, create MiraAccount
    public fun connect_account(account: &signer) {
        let account_addr = address_of(account);
        if (!exists<MiraAccount>(account_addr)) {
            let new_mira_account =
                MiraAccount {
                    owner: account_addr,
                    account_name: b"random_name_generator",
                    total_funds_invested: 0,
                    funds_under_management: 0,
                    funds_on_gas: 0,
                    funds_on_management: 0,
                    created_pools: table::new<u64, MiraPool>(),
                    invested_pools: table::new<u64, MiraPool>(),
                };
            move_to(account, new_mira_account)
        }
    }

    // create resource account for the MiraPool, move MiraPool and send funds to the resource account,
    // and index the resouce account in Pools so that user can access pool.
    public fun create_pool(manager: &signer, amount: u64, s: vector<u8>, pool_name: vector<u8>,
                           index_allocation: Table<vector<u8>, u64>, settings: MiraPoolSettings) acquires Pools {
        let (resource_signer, signer_capability) = create_resource_account(manager, s);
        coin::register<AptosCoin>(&resource_signer);

        let investors = table::new<address, u64>();
        table::add(&mut investors, address_of(manager), amount);

        move_to(
            &resource_signer,
            MiraPool {
                pool_name,
                pool_address: address_of(&resource_signer),
                manager: address_of(manager),
                investors,
                amount,
                index_allocation,
                signer_capability,
                settings
            }
        );

        coin::transfer<AptosCoin>(manager, address_of(&resource_signer), amount);

        let pools = borrow_global_mut<Pools>(address_of(manager));
        table::add(&mut pools.pool_accounts, pool_name, address_of(&resource_signer));
        pools.length = pools.length + 1;
    }

    public fun choose_pool_settings( management_fee: u8, rebalancing_period: u8, minimum_contribution: u8,
        minimum_withdrawal: u8, referral_reward: u8): MiraPoolSettings {
            MiraPoolSettings{
                management_fee, rebalancing_period, minimum_contribution,
                minimum_withdrawal, referral_reward
            }
    }

    public fun change_account_name(account: &signer, name: vector<u8>)acquires MiraAccount {
        let mira_acct = borrow_global_mut<MiraAccount>(address_of(account));
        mira_acct.account_name =name;
    }
}

#[test_only]
module std::LessSimpleMiraTests {
    use std::unit_test;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use std::signer::address_of;
    use aptos_framework::coin::{deposit, BurnCapability, MintCapability};
    use 0x1::LessSimpleMira::{create_pool, init, connect_account, change_account_name, choose_pool_settings, MiraPoolSettings};
    use aptos_std::table::Table;
    use aptos_std::table;

    #[test(core_framework = @aptos_framework)]
    public entry fun first_test(core_framework: signer) {
        let (alice, _) = create_two_signers();
        let (burn_cap, mint_cap) = setup_test_account(&alice, &core_framework);

        let (settings, settings2) = generate_pool_settings();
        let (allocation, allocation2) = generate_allocations();

        init(&alice);
        connect_account(&alice);
        change_account_name(&alice, b"alice");
        create_pool(&alice, 100, b"seed1", b"pool1", allocation, settings);
        create_pool(&alice, 200, b"seed2", b"pool2", allocation2, settings2);

        terminate_test(burn_cap, mint_cap)
    }

    #[test_only]
    fun create_two_signers(): (signer, signer) {
        let signers = &mut unit_test::create_signers_for_testing(2);
        (vector::pop_back(signers), vector::pop_back(signers))
    }

    #[test_only]
    fun generate_allocations(): (Table<vector<u8>, u64>, Table<vector<u8>, u64>){
        let newallocations = table::new<vector<u8>, u64>();
            table::add<vector<u8>, u64>(&mut newallocations, b"APTOS", 50);
            table::add<vector<u8>, u64>(&mut newallocations, b"BTC", 50);
        let newallocations2 = table::new<vector<u8>, u64>();
            table::add<vector<u8>, u64>(&mut newallocations2, b"APTOS", 25);
            table::add<vector<u8>, u64>(&mut newallocations2, b"BTC", 75);

        (newallocations, newallocations2)
    }

    #[test_only]
    fun generate_pool_settings(): (MiraPoolSettings, MiraPoolSettings){
        let settings = choose_pool_settings(1, 10,
            5, 0, 0);
        let settings2 = choose_pool_settings(2, 5,
            0, 10, 0);

        (settings, settings2)
    }

    #[test_only]
    fun setup_test_account(account: &signer, core_framework: &signer): (BurnCapability<AptosCoin>, MintCapability<AptosCoin>){
        aptos_framework::aptos_account::create_account(address_of(account));
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(core_framework);
        deposit(address_of(account), coin::mint(1000, &mint_cap));
        (burn_cap, mint_cap)
    }

    #[test_only]
    fun terminate_test(burn_cap: BurnCapability<AptosCoin>, mint_cap: MintCapability<AptosCoin>) {
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
    }
}