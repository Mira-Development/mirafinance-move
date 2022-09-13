module mira::mira{
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::table;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    
    const MODULE_ADMIN: address = @mira;

    const INVALID_ADMIN_ADDRESS: u64 = 1;
    const INVALID_ACCOUNT_NAME: u64 = 2;   
   
    struct MiraStatus has key {
        create_pool_events: EventHandle<MiraPoolCreateEvent>
    }

    struct MiraPool has key, store {
        pool_name: string::String,
        pool_address: address,
        manager: address,
        investors: table::Table<address, u64>,
        index_allocation: table::Table<string::String, u8>,
        amount: u64,
        private_allocation: bool,
        settings: MiraPoolSettings
    }

    struct MiraPoolSettings has store, copy, drop {
        management_fee: u64,
        rebalancing_period: u8,
        minimum_contribution: u64,
        minimum_withdrawal: u64,
        referral_reward: u64
    }

    struct MiraAccount has key {
        owner: address,
        account_name: string::String,
        total_funds_invested: u64,
        funds_under_management: u64,
        funds_on_gas: u64,
        funds_on_management: u64,
        created_pools: table::Table<string::String, account::SignerCapability>,
        invested_pools: table::Table<string::String, account::SignerCapability>
    }

    //emit during creating pool
    struct MiraPoolCreateEvent has store, drop {
        pool_name: string::String,
        pool_owner: address,
        pool_address: address,
        private_allocation: bool,
        management_fee: u64,
        founded: u64
    }

    public entry fun init_mira(admin: &signer){
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        move_to(admin, MiraStatus{
            create_pool_events: account::new_event_handle<MiraPoolCreateEvent>(admin)
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
                created_pools: table::new<string::String, account::SignerCapability>(),
                invested_pools: table::new<string::String, account::SignerCapability>()
            })
        }
    }

    fun choose_pool_settings( management_fee: u64, rebalancing_period: u8, minimum_contribution: u64,
        minimum_withdrawal: u64, referral_reward: u64): MiraPoolSettings {
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
        amount: u64,
        management_fee: u64,
        rebalancing_period: u8,
        minimum_contribution: u64,
        minimum_withdrawal: u64,
        referral_reward: u64,
        index_allocation_key: vector<string::String>,
        index_allocation_value: vector<u8>,
        private_allocation: bool
    ) acquires MiraAccount, MiraStatus {
        let manager_addr = signer::address_of(manager);
        let mira_account = borrow_global_mut<MiraAccount>(signer::address_of(manager));
        assert!(!table::contains(&mut mira_account.created_pools, string::utf8(pool_name)), 1);
        
        let (pool_signer, pool_signer_capability) = account::create_resource_account(manager, pool_name);
        coin::register<AptosCoin>(&pool_signer);

        let settings = choose_pool_settings( management_fee, rebalancing_period, minimum_contribution, minimum_withdrawal, referral_reward);
        let investors = table::new<address, u64>();
        table::add(&mut investors, manager_addr, amount);

        let index_allocation = table::new<string::String, u8>();
        let i = 0;
        while (i < vector::length(&index_allocation_key)){
            table::add(&mut index_allocation, *vector::borrow(&index_allocation_key, i), *vector::borrow(&index_allocation_value, i));
            i = i + 1;
        };

        move_to(&pool_signer,
            MiraPool{
                pool_name: string::utf8(pool_name),
                pool_address: signer::address_of(&pool_signer),
                manager: manager_addr,
                investors,
                index_allocation,
                amount,
                private_allocation,
                settings
            }
        );

        mira_account.total_funds_invested = mira_account.total_funds_invested + amount;

        coin::transfer<AptosCoin>(manager, signer::address_of(&pool_signer), amount);
        table::add(&mut mira_account.created_pools, string::utf8(pool_name), pool_signer_capability);
	
	let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        event::emit_event<MiraPoolCreateEvent>(
            &mut miraStatus.create_pool_events,
            MiraPoolCreateEvent{
               pool_name: string::utf8(pool_name),
               pool_owner: manager_addr,
               pool_address: signer::address_of(&pool_signer),
               private_allocation,
               management_fee,
               founded: timestamp::now_seconds()
            }
        )
    }
    
    public entry fun invest(investor: &signer, pool_name: vector<u8>, pool_owner: address, amount: u64) acquires MiraPool, MiraAccount {
        let investor_addr = signer::address_of(investor);
        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let pool_signer_capability = table::borrow_mut<string::String, account::SignerCapability>( &mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(signer::address_of(&pool_signer));

        let curramount = 0;
        if (table::contains(&mut mira_pool.investors, investor_addr)){
            curramount = *table::borrow(&mira_pool.investors, investor_addr);
        };
        table::upsert(&mut mira_pool.investors, investor_addr, curramount + amount);
        mira_pool.amount = mira_pool.amount + amount;        
        coin::transfer<AptosCoin>(investor, signer::address_of(&pool_signer), amount);
    }
    
    public entry fun withdraw(investor: &signer, pool_name: vector<u8>, pool_owner: address, amount: u64) acquires MiraPool, MiraAccount {
        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let pool_signer_capability = table::borrow_mut<string::String, account::SignerCapability>( &mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(signer::address_of(&pool_signer));
        
        let value = table::borrow(&mut mira_pool.investors, signer::address_of(investor));
        
        mira_pool.amount = mira_pool.amount - amount;
        coin::transfer<AptosCoin>(&pool_signer, signer::address_of(investor), amount);
        table::upsert(&mut mira_pool.investors, signer::address_of(investor), *value - amount);        
    }
}
