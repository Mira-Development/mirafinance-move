module 0x1::SimpleMira {
    use std::signer::address_of;
    use aptos_std::table::Table;
    use aptos_std::table;
    use aptos_framework::account::create_resource_account;

    struct Pools has key {
        pool_accounts: Table<u64, address>,
        length: u64
    }

    struct MiraPool has key, store {
        pool_name: vector<u8>,
        pool_address: address,
        manager: address,
        investors: Table<address, u64>,
        index_allocation: Table<vector<u8>, u64>,
        total_amount: u8,
        settings: MiraPoolSettings
    }

    struct MiraPoolSettings has store, copy, drop {
        management_fee: u8,
        rebalancing_period: u8,
        minimum_contribution: u8,
        minimum_withdrawal: u8,
        referral_reward: u8
    }

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

    public fun init(account:&signer) {
        let pools = Pools{
            pool_accounts: table::new<u64, address>(),
            length: 0
        };
        move_to(account, pools);
//        move_to(*ADMIN, copy Accounts);
//        move_to(*ADMIN, copy Pools);
    }

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

    public fun choose_pool_settings( management_fee: u8, rebalancing_period: u8, minimum_contribution: u8,
        minimum_withdrawal: u8, referral_reward: u8): MiraPoolSettings {
            MiraPoolSettings{
                management_fee, rebalancing_period, minimum_contribution,
                minimum_withdrawal, referral_reward
            }
    }

    public fun create_pool(
        manager: &signer,
        pool_name: vector<u8>,
        index_allocation: Table<vector<u8>, u64>,
        total_amount: u8,
        settings: MiraPoolSettings) acquires Pools, MiraAccount {

        let (resource_signer, _) = create_resource_account(manager, b"seed1");

        let investors = table::new<address, u64>();
        table::add(&mut investors, address_of(manager), (total_amount as u64));

        move_to(&resource_signer,
            MiraPool {
                pool_name,
                pool_address: address_of(&resource_signer),
                manager: address_of(manager),
                investors,
                index_allocation,
                total_amount,
                settings
            }
        );

        let pools = borrow_global_mut<Pools>(address_of(manager));
        table::add(&mut pools.pool_accounts, pools.length, address_of(&resource_signer));
        pools.length = pools.length + 1;

        let mira_acct = borrow_global_mut<MiraAccount>(address_of(manager));
        mira_acct.total_funds_invested = mira_acct.total_funds_invested + total_amount;
    }

    public fun change_account_name(account: &signer, name: vector<u8>)acquires MiraAccount {
        let mira_acct = borrow_global_mut<MiraAccount>(address_of(account));
        mira_acct.account_name =name;
    }
}

#[test_only]
module 0x1::SimpleMiraTests {
    use std::unit_test;
    use std::vector;
    use std::SimpleMira::{choose_pool_settings, create_pool};
    use aptos_std::table;
    use 0x1::SimpleMira::{init, connect_account, change_account_name};

    #[test]
    public entry fun create_actual_pool() {
        let (alice, _) = create_two_signers();

        init(&alice);
        connect_account(&alice);
        change_account_name(&alice, b"alice");

        let newallocations = table::new<vector<u8>, u64>();
            table::add<vector<u8>, u64>(&mut newallocations, b"APTOS", 50);
            table::add<vector<u8>, u64>(&mut newallocations, b"BTC", 50);

//        let newallocations2 = table::new<vector<u8>, u64>();
//            table::add<vector<u8>, u64>(&mut newallocations2, b"APTOS", 25);
//            table::add<vector<u8>, u64>(&mut newallocations2, b"BTC", 75);

        let settings = choose_pool_settings(
            1,
            10,
            5,
            0,
            0);

//        let settings2 = choose_pool_settings(
//            1,
//            10,
//            5,
//            0,
//            0);

        create_pool(
            &alice,
            b"3",
            newallocations,
            100,
            settings);

//        create_pool(
//            &alice,
//            b"4",
//            newallocations2,
//            100,
//            settings);
    }

    #[test_only]
    fun create_two_signers(): (signer, signer) {
        let signers = &mut unit_test::create_signers_for_testing(2);
        (vector::pop_back(signers), vector::pop_back(signers))
    }
}
