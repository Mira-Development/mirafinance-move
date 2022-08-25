module 0x1::SimpleMira {
    use std::signer::address_of;
    use aptos_framework::table::Table;
    use aptos_framework::table;
    use 0x1::LiquidityPool::init_lp;

    const ADMIN: address = @mira;

    struct Pools has key {
        items: Table<address, Table<u64, MiraPool>>
    }

    struct Accounts has key {
        items: Table<address, MiraAccount>
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

    public fun choose_pool_settings(
        management_fee: u8,
        rebalancing_period: u8,
        minimum_contribution: u8,
        minimum_withdrawal: u8,
        referral_reward:u8): MiraPoolSettings {

        let newsettings = MiraPoolSettings{
            management_fee,
            rebalancing_period,
            minimum_contribution,
            minimum_withdrawal,
            referral_reward
        };

        return newsettings
    }

    public fun create_pool(
        manager: &signer,
        pool_name: vector<u8>,
        index_allocation: Table<vector<u8>, u64>,
        total_amount: u8,
        settings: MiraPoolSettings): MiraPool {

        let pool_address = address_of(&init_lp(manager));

        let investors = table::new<address, u64>();

        let newpool = MiraPool {
            pool_name,
            pool_address,
            manager: address_of(manager),
            investors,
            index_allocation,
            total_amount,
            settings
        };

        return newpool
    }


}

#[test_only]
module std::SimpleMiraTests {
    use std::unit_test;
    use std::vector;
    use std::signer;
    use std::SimpleMira::{choose_pool_settings, create_pool, MiraPool};
    use std::signer::address_of;
    use std::debug::print;
    use aptos_framework::table;
    use aptos_framework::table::Table;

    #[test]
    public entry fun create_actual_pool() {
        let (mira, bob) = create_two_signers();

        let newallocations = table::new<vector<u8>, u64>();
            table::add<vector<u8>, u64>(&mut newallocations, b"APTOS", 50);
            table::add<vector<u8>, u64>(&mut newallocations, b"BTC", 50);

        let settings = choose_pool_settings(
            1,
            10,
            5,
            0,
            0);

        let pool = create_pool(
            &mira,
            b"firstpool",
            newallocations,
            100,
            settings);

        move_to(&mira, pool);
    }

    #[test_only]
    fun create_two_signers(): (signer, signer) {
        let signers = &mut unit_test::create_signers_for_testing(2);
        (vector::pop_back(signers), vector::pop_back(signers))
    }
}
