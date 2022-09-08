module mira::mira{
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::table;
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};

    const MODULE_ADMIN: address = @mira;

    const INVALID_ADMIN_ADDRESS: u64 = 1;
    const INVALID_ACCOUNT_NAME: u64 = 2;   
   
    struct MiraStatus has key {
        cap: account::SignerCapability,
        create_pool_events: EventHandle<MiraPoolCreateEvent>
    }

    struct Pools has key {
        pool_accounts: table::Table<u64, address>, // mapping index + address
        length: u64
    }

    struct MiraPool has key, store {
        pool_name: string::String,
        pool_address: address,
        manager: address,
        investors: table::Table<address, u64>,
        index_allocation: table::Table<string::String, u8>,
        total_amount: u64,
        settings: MiraPoolSettings
    }

    struct MiraPoolSettings has store, copy, drop {
        management_fee: u8,
        rebalancing_period: u8,
        minimum_contribution: u8,
        minimum_withdrawal: u8,
        referral_reward: u8
    }

    struct MiraAccount has key {
        owner: address,
        account_name: string::String,
        total_funds_invested: u64,
        funds_under_management: u64,
        funds_on_gas: u64,
        funds_on_management: u64,
        created_pools: table::Table<u64, MiraPool>,
        invested_pools: table::Table<u64, MiraPool>
    }

    //emit during creating pool
    struct MiraPoolCreateEvent has store, drop {
        pool_name: string::String,
        pool_address: address
    }

    public entry fun init_mira(admin: &signer){
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);
        //ceate resource_account
        let ( resource_account, signer_capability) = account::create_resource_account(
            admin,
            vector<u8>[1,1,1]
        );

        move_to(admin, MiraStatus{
            cap: signer_capability,
            create_pool_events: account::new_event_handle<MiraPoolCreateEvent>(admin)
        });

        move_to(&resource_account, Pools{
            pool_accounts: table::new<u64, address>(),
            length: 0
        });

    }

    public entry fun connect_account( user: &signer ) {
        let user_addr = signer::address_of(user);
        if ( !exists<MiraAccount>(user_addr) ){
            move_to( user, MiraAccount{
                owner: user_addr,
                account_name: string::utf8(b"random_name_generator"),
                total_funds_invested: 0,
                funds_under_management: 0,
                funds_on_gas: 0,
                funds_on_management: 0,
                created_pools: table::new<u64, MiraPool>(),
                invested_pools: table::new<u64, MiraPool>()
            })
        }
    }

    fun choose_pool_settings( management_fee: u8, rebalancing_period: u8, minimum_contribution: u8,
        minimum_withdrawal: u8, referral_reward: u8): MiraPoolSettings {
        MiraPoolSettings {
            management_fee, rebalancing_period, minimum_contribution, minimum_withdrawal, referral_reward
        }
    }

    public entry fun change_account_name( user: &signer, name: vector<u8> ) acquires MiraAccount {
        assert!(vector::length(&name) >0, INVALID_ACCOUNT_NAME);
        let mira_acct = borrow_global_mut<MiraAccount>(signer::address_of(user));
        mira_acct.account_name = string::utf8(name);
    }
    
    public entry fun create_pool(
        manager: &signer,
        pool_name: vector<u8>,
        total_amount: u64,
        management_fee: u8,
        rebalancing_period: u8,
        minimum_contribution: u8,
        minimum_withdrawal: u8,
        referral_reward: u8,
        index_allocation_key: vector<string::String>,
        index_allocation_value: vector<u8>
    ) acquires Pools, MiraStatus, MiraAccount {
        let manager_addr = signer::address_of(manager);
        let (resource_account, _) = account::create_resource_account(manager, b"seed1");

        let settings = choose_pool_settings( management_fee, rebalancing_period, minimum_contribution, minimum_withdrawal, referral_reward);
        let investors = table::new<address, u64>();
        table::add(&mut investors, manager_addr, total_amount);

        let index_allocation = table::new<string::String, u8>();
        let i = 0;
        while (i < vector::length(&index_allocation_key)){
            table::add(&mut index_allocation, *vector::borrow(&index_allocation_key, i), *vector::borrow(&index_allocation_value, i));
            i = i + 1;
        };

        move_to(&resource_account,
            MiraPool{
                pool_name: string::utf8(pool_name),
                pool_address: signer::address_of(&resource_account),
                manager: manager_addr,
                investors,
                index_allocation,
                total_amount,
                settings
            }
        );

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);

        let resource_account_admin = account::create_signer_with_capability(&miraStatus.cap);
        let pools = borrow_global_mut<Pools>(signer::address_of(&resource_account_admin));
        table::add(&mut pools.pool_accounts, pools.length, signer::address_of(&resource_account));
        pools.length = pools.length + 1;

        let mira_account = borrow_global_mut<MiraAccount>(signer::address_of(manager));
        mira_account.total_funds_invested = mira_account.total_funds_invested + total_amount;
    }
}
