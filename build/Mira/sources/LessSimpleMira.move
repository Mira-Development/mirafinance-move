module 0x1::LessSimpleMira {
    use std::signer::address_of;
    use aptos_framework::account::{create_resource_account, SignerCapability, create_signer_with_capability};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::table::{Table};
    use aptos_std::table;
    use aptos_std::iterable_table::{IterableTable};
    use std::string::String;
    use std::string;

    // when a user creates a pool, a resource account is created to manage the pool funds
    // the Pools struct stores the resource accounts (addresses) of a user's created pools
    // to access a pool, let user_pools = borrow_global_mut<Pools>(address_of(useraccount)).pool_accounts ->
    // let specific_pool_resource_account = table::borrow_mut<String, address>(user_pool_resources, poolname)
    // view MiraPool: borrow_global_mut<MiraPool>(address_of(specific_pool_resource_account))

    struct MiraPool has key, store {
        pool_name: String,
        pool_address: address,
        manager: address,
        investors: Table<address, u64>,
        index_allocation: IterableTable<String, u64>,
        amount: u64,
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
        account_name: String,
        total_funds_invested: u8,
        funds_under_management: u8,
        funds_on_gas: u8,
        funds_on_management: u8,
        created_pools: Table<String, SignerCapability>,
        invested_pools: Table<String, SignerCapability>,
    }

    // check if account has already connected to Mira Dapp;
    // if not, create MiraAccount
    public fun connect_account(account: &signer) {
        let account_addr = address_of(account);
        if (!exists<MiraAccount>(account_addr)) {
            let new_mira_account =
                MiraAccount {
                    owner: account_addr,
                    account_name: string::utf8(b"random_name_generator"),
                    total_funds_invested: 0,
                    funds_under_management: 0,
                    funds_on_gas: 0,
                    funds_on_management: 0,
                    created_pools: table::new<String, SignerCapability>(),
                    invested_pools: table::new<String, SignerCapability>(),
                };
            move_to(account, new_mira_account)
        }
    }

    // create resource account for the MiraPool, move MiraPool and send funds to the resource account,
    // and index the resouce account in Pools so that user can access pool.
    public fun create_pool(manager: &signer, amount: u64, pool_name: String,
                           index_allocation: IterableTable<String, u64>, settings: MiraPoolSettings) acquires MiraAccount {
        let account = borrow_global_mut<MiraAccount>(address_of(manager));
        assert!(!table::contains(&mut account.created_pools, pool_name), 0);

        let (resource_signer, signer_capability) =
            create_resource_account(manager, *string::bytes(&pool_name));
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
                settings
            }
        );

        coin::transfer<AptosCoin>(manager, address_of(&resource_signer), amount);
        table::add(&mut account.created_pools, pool_name, signer_capability);
    }

    public fun choose_pool_settings( management_fee: u8, rebalancing_period: u8, minimum_contribution: u8,
        minimum_withdrawal: u8, referral_reward: u8): MiraPoolSettings {
            MiraPoolSettings{
                management_fee, rebalancing_period, minimum_contribution,
                minimum_withdrawal, referral_reward
            }
    }

    public fun invest(investor: &signer, poolname: String, poolowner: address, amount: u64)acquires MiraPool, MiraAccount {
        let owner = borrow_global_mut<MiraAccount>(poolowner);
        let specific_pool_resource_account = table::borrow_mut<String, SignerCapability>(
            &mut owner.created_pools, poolname);
        let newsigner = create_signer_with_capability(specific_pool_resource_account);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&newsigner));

        let curramount = 0;
        if (table::contains(&mut mira_pool.investors,address_of(investor))){
            curramount = *table::borrow(&mira_pool.investors, address_of(investor));
        };
        table::upsert(&mut mira_pool.investors, address_of(investor), curramount + amount);

        mira_pool.amount = mira_pool.amount + amount;
        coin::transfer<AptosCoin>(investor, address_of(&newsigner), amount);
    }

    public fun withdraw(investor: &signer, poolname: String, poolowner: address, amount: u64)acquires MiraPool, MiraAccount {
        let owner = borrow_global_mut<MiraAccount>(poolowner);
        let specific_pool_resource_account = table::borrow_mut<String, SignerCapability>(
            &mut owner.created_pools, poolname);
        let newsigner = create_signer_with_capability(specific_pool_resource_account);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&newsigner));

        let value = table::borrow(&mut mira_pool.investors, address_of(investor));
        mira_pool.amount = mira_pool.amount - amount;
        coin::transfer<AptosCoin>(&newsigner, address_of(investor), amount);
        table::upsert(&mut mira_pool.investors, address_of(investor), *value - amount);
    }

    public fun change_pool_settings(manager: &signer, poolname: String, newsettings: MiraPoolSettings) acquires MiraAccount, MiraPool {
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let specific_pool_resource_account = table::borrow_mut<String, SignerCapability>(
            &mut owner.created_pools, poolname);
        let newsigner = create_signer_with_capability(specific_pool_resource_account);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&newsigner));
        mira_pool.settings = newsettings;
    }

//    public fun change_pool_allocation(manager: &signer, poolname: String, newallocation: IterableTable<String, u64>) acquires Pools, MiraPool {
//        let user_pool_resources = borrow_global_mut<Pools>(address_of(manager));
//        let specific_pool_resource_account = table::borrow_mut<String, SignerCapability>(
//            &mut user_pool_resources.pool_accounts, poolname);
//        let newsigner = create_signer_with_capability(specific_pool_resource_account);
//        let mira_pool = borrow_global_mut<MiraPool>(address_of(&newsigner));
//        let oldtokens = &mira_pool.index_allocation;
//        oldtokens = &newallocation;
//        //swap_tables(oldtokens, newallocation);
//        //mira_pool.index_allocation = newallocation;
//    }

    public fun change_account_name(account: &signer, name: String)acquires MiraAccount {
        let mira_acct = borrow_global_mut<MiraAccount>(address_of(account));
        mira_acct.account_name =name;
    }

//    public fun swap_tables(table1: &IterableTable<vector<u8>, u64>, table2: IterableTable<vector<u8>, u64>){
//        let key = iterable_table::tail_key(table1);
//        while (option::is_some(&key)) {
//            let (_, prev, _) = iterable_table::remove_iter(table1, *option::borrow(&key));
//            key = prev;
//        };
//
////        key = iterable_table::tail_key(&table2);
////        while (option::is_some(&key)) {
////            let (val, prev, _) = iterable_table::remove_iter(&mut table2, *option::borrow(&key));
////            key = prev;
////        };
////        while (i < iterable_table::length(&table1)) {
////            iterable_table::remove(&mut table, i);
////            i = i + 2;
////        };
//    }
}

#[test_only]
module std::LessSimpleMiraTests {
    use std::unit_test;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use std::signer::address_of;
    use aptos_framework::coin::{deposit, BurnCapability, MintCapability};
    use 0x1::LessSimpleMira::{create_pool, connect_account, change_account_name, choose_pool_settings, MiraPoolSettings, change_pool_settings, invest, withdraw};
    use aptos_std::iterable_table;
    use aptos_std::iterable_table::IterableTable;
    use std::string;
    use std::string::String;
    use aptos_framework::account;

    // demonstration of several features gone right:
    // - create and update MiraAccounts when connecting to Dapp
    // - create and update MiraPools
    // - store coins in a separate resource account for each pool
    // - invest in another user's pool
    // - invest in your own pool (as manager)
    // - withdraw funds from another user's pool
    // - withdraw from your own pool (as manager)
    #[test(core_framework = @aptos_framework)]
    public entry fun first_test(core_framework: signer) {
        let (mira, _) = create_two_signers();
        let (burn_cap, mint_cap) =
            setup_test_account(&mira, &core_framework, 5000);

        let alice = account::create_account_for_test(@0x25);
        coin::register<AptosCoin>(&alice);
        coin::transfer<AptosCoin>(&mira, address_of(&alice), 1000);

        let bob = account::create_account_for_test(@0x26);
        coin::register<AptosCoin>(&bob);
        coin::transfer<AptosCoin>(&mira, address_of(&bob), 1000);

        let (settings, settings2) = generate_pool_settings();
        let (allocation, allocation2, allocation3) = generate_allocations();

        connect_account(&mira);
        change_account_name(&mira, string::utf8(b"mira"));
        create_pool(&mira, 100, string::utf8(b"mira_first_pool"), allocation, settings);
        create_pool(&mira, 200, string::utf8(b"mira_second_pool"), allocation2, settings2);
        change_pool_settings(&mira, string::utf8(b"mira_second_pool"), settings);

        connect_account(&alice);
        change_account_name(&alice, string::utf8(b"alice"));
        create_pool(&alice, 200, string::utf8(b"alice_first_pool"), allocation3, settings2);
        invest(&alice, string::utf8(b"alice_first_pool"), address_of(&alice), 100);
        withdraw(&alice, string::utf8(b"alice_first_pool"), address_of(&alice), 100);
        invest(&alice, string::utf8(b"mira_first_pool"), address_of(&mira), 100);

        connect_account(&bob);
        change_account_name(&bob, string::utf8(b"bob"));
        invest(&bob, string::utf8(b"alice_first_pool"), address_of(&alice), 100);
        invest(&bob, string::utf8(b"mira_first_pool"), address_of(&mira), 200);
        withdraw(&bob, string::utf8(b"mira_first_pool"), address_of(&mira), 100);

        terminate_test(burn_cap, mint_cap);
    }

    #[test_only]
    fun create_two_signers(): (signer, signer) {
        let signers = &mut unit_test::create_signers_for_testing(2);
        (vector::pop_back(signers), vector::pop_back(signers))
    }

    #[test_only]
    fun generate_allocations(): (IterableTable<String, u64>, IterableTable<String, u64>, IterableTable<String, u64>){
        let newallocations = iterable_table::new<String, u64>();
            iterable_table::add<String, u64>(&mut newallocations, string::utf8(b"APTOS"), 50);
            iterable_table::add<String, u64>(&mut newallocations, string::utf8(b"BTC"), 50);
        let newallocations2 = iterable_table::new<String, u64>();
            iterable_table::add<String, u64>(&mut newallocations2, string::utf8(b"APTOS"), 25);
            iterable_table::add<String, u64>(&mut newallocations2, string::utf8(b"BTC"), 75);
        let newallocations3 = iterable_table::new<String, u64>();
            iterable_table::add<String, u64>(&mut newallocations3, string::utf8(b"APTOS"), 25);
            iterable_table::add<String, u64>(&mut newallocations3, string::utf8(b"ETH"), 25);
            iterable_table::add<String, u64>(&mut newallocations3, string::utf8(b"BTC"), 50);
        (newallocations, newallocations2, newallocations3)
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
    fun setup_test_account(account1: &signer, core_framework: &signer, amount: u64): (BurnCapability<AptosCoin>, MintCapability<AptosCoin>){
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(core_framework);
        aptos_framework::aptos_account::create_account(address_of(account1));
        deposit(address_of(account1), coin::mint(amount, &mint_cap));
        (burn_cap, mint_cap)
    }

    #[test_only]
    fun terminate_test(burn_cap: BurnCapability<AptosCoin>, mint_cap: MintCapability<AptosCoin>) {
        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
    }
}