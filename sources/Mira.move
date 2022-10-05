module mira::mira {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use liquidswap::router;
    use liquidswap::curves::Uncorrelated;
    use test_coins::coins::BTC;
    use std::string::String;
    use aptos_std::debug;
    use aptos_framework::account::SignerCapability;
    use aptos_std::table::Table;
    use std::signer::address_of;
    use aptos_std::table_with_length;
    use aptos_std::table_with_length::TableWithLength;

    const MODULE_ADMIN: address = @mira;

    const INVALID_ADMIN_ADDRESS: u64 = 1;
    const INVALID_ACCOUNT_NAME: u64 = 2;
    const INSUFFICIENT_FUNDS: u64 = 3;
    const INVALID_PARAMETER: u64 = 4;
    const DUPLICATE_NAME: u64 = 5;

    struct MiraStatus has key {
        create_pool_events: EventHandle<MiraPoolCreateEvent>,
        deposit_pool_events: EventHandle<MiraPoolDepositEvent>,
        withdraw_pool_events: EventHandle<MiraPoolWithdrawEvent>
    }

    struct MiraPool has key, store {
        pool_name: String,
        created: u64, //in seconds
        pool_address: address,
        manager: address,
        investors: Table<address, u64>,
        index_allocation: Table<String, u8>,
        amount: u64,
        deposit_fee: u64,
        private_allocation: bool,
        settings: MiraPoolSettings,
        tokens: TableWithLength<u64, String>,
        token_allocations: TableWithLength<u64, u64>,
        funds: u64,
        gas_funds: u64,
    }

    struct MiraPoolSettings has store, copy, drop {
        management_fee: u64,
        rebalancing_period: u64,
        minimum_contribution: u64,
        minimum_withdrawal: u64,
        private_fund: u64,
        private_allocation: u64,
        gas_allocation: u64
    }

    struct MiraAccount has key {
        owner: address,
        account_name: String,
        total_funds_invested: u64,
        funds_under_management: u64,
        funds_on_gas: u64,
        funds_on_management: u64,
        created_pools: Table<String, SignerCapability>,
        invested_pools: Table<String, SignerCapability>
    }

    //emit during creating pool
    struct MiraPoolCreateEvent has store, drop {
        pool_name: String,
        pool_owner: address,
        pool_address: address,
        private_allocation: u64,
        management_fee: u64,
        founded: u64,
        timestamp: u64
    }
    //
    struct MiraPoolDepositEvent has store, drop {
        pool_name: String,
        investor: address,
        amount: u64,
        timestamp: u64
    }

    struct MiraPoolWithdrawEvent has store, drop {
        pool_name: String,
        investor: address,
        amount: u64,
        timestamp: u64
    }

    public entry fun init_mira(admin: &signer) {
        let admin_addr = address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        move_to(admin, MiraStatus{
            create_pool_events: account::new_event_handle<MiraPoolCreateEvent>(admin),
            deposit_pool_events: account::new_event_handle<MiraPoolDepositEvent>(admin),
	          withdraw_pool_events: account::new_event_handle<MiraPoolWithdrawEvent>(admin)            
        });
    }

    public entry fun connect_account(user: &signer, account_name: vector<u8>) {
        let user_addr = address_of(user);
        if ( !exists<MiraAccount>(user_addr) ) {
            move_to(user, MiraAccount {
                owner: user_addr,
                account_name: string::utf8(account_name),
                total_funds_invested: 0,
                funds_under_management: 0,
                funds_on_gas: 0,
                funds_on_management: 0,
                created_pools: table::new<String, SignerCapability>(),
                invested_pools: table::new<String, SignerCapability>()
            })
        };
    }

    public entry fun create_pool_settings(management_fee: u64, rebalancing_period: u64, minimum_contribution: u64,
                  minimum_withdrawal: u64, private_fund: u64, private_allocation: u64, gas_allocation: u64): MiraPoolSettings {
        assert!(management_fee <= 10000, INVALID_PARAMETER); //100%
        assert!(gas_allocation <= 10000, INVALID_PARAMETER); //100%
        assert!(minimum_contribution >= 5, INVALID_PARAMETER); //$5

        MiraPoolSettings {
            management_fee, rebalancing_period, minimum_contribution, minimum_withdrawal, private_fund, private_allocation, gas_allocation
        }
    }

    public entry fun print_pool_info(user: &signer, pool_name: String) acquires MiraAccount, MiraPool {
        let acct = borrow_global_mut<MiraAccount>(signer::address_of(user));
        let signercap = table::borrow(&acct.created_pools, pool_name);
        let pool_signer = account::create_signer_with_capability(signercap);
        let mira_pool = borrow_global_mut<MiraPool>(signer::address_of(&pool_signer));
        debug::print(mira_pool);
    }

    public entry fun print_account_info(user: &signer)acquires MiraAccount {
        let acct = borrow_global_mut<MiraAccount>(signer::address_of(user));
        debug::print(acct);
    }

    // this should happen on backend, shouldn't charge user gas to change account name
    public entry fun change_account_name( user: &signer, name: vector<u8> ) acquires MiraAccount {
        assert!(vector::length(&name) >0, INVALID_ACCOUNT_NAME);
        let mira_acct = borrow_global_mut<MiraAccount>(address_of(user));
        mira_acct.account_name = string::utf8(name);
    }

    public entry fun create_pool(
        manager: &signer,
        pool_name: vector<u8>,
        amount: u64,
        deposit_fee: u64,
        management_fee: u64,
        rebalancing_period: u8,
        minimum_contribution: u64,
        minimum_withdrawal: u64,
        referral_reward: u64,
        index_allocation_key: vector<String>,
        index_allocation_value: vector<u8>,
        private_allocation: bool,
        tokens: TableWithLength<u64, String>,
        token_allocations: TableWithLength<u64, u64>,
        funds: u64,
    ) acquires MiraAccount, MiraStatus {
        let gas_funds = funds * (settings.gas_allocation/ 10000);
        let funds = funds - gas_funds;

        let manager_addr = address_of(manager);
        let mira_account = borrow_global_mut<MiraAccount>(address_of(manager));

        assert!(!table::contains(&mut mira_account.created_pools, string::utf8(pool_name)), DUPLICATE_NAME);
        // check that pool_name is unique
        assert!(!string::is_empty(&string::utf8(pool_name)), INVALID_PARAMETER);
        assert!(amount > 0, INVALID_PARAMETER);
        assert!(deposit_fee > 0, INVALID_PARAMETER);

        let (pool_signer, pool_signer_capability) = account::create_resource_account(manager, pool_name);
        coin::register<AptosCoin>(&pool_signer);

        let investors = table_with_length::new<address, u64>();
        table_with_length::add(&mut investors, manager_addr, funds);

        let index_allocation = table::new<String, u8>();
        let i = 0;
        let total_allocation = 0;
        assert!(table_with_length::length(&tokens) == table_with_length::length(&token_allocations), INVALID_PARAMETER);

        while (i < table_with_length::length(&token_allocations)) {
            let index = *table_with_length::borrow(&tokens, i);
            assert!(!string::is_empty(&index), INVALID_PARAMETER);
            total_allocation = total_allocation + *table_with_length::borrow(&token_allocations, i);
            assert!(total_allocation <= 100, INVALID_PARAMETER);
            i = i + 1;
        };
        assert!(total_allocation == 100, INVALID_PARAMETER);
        let created = timestamp::now_seconds();
        move_to(&pool_signer,
            MiraPool {
                pool_name: string::utf8(pool_name),
                pool_address: address_of(&pool_signer),
                manager: manager_addr,
                created,
                investors,
                index_allocation,
                amount,
                deposit_fee,
                private_allocation,
                tokens,
                token_allocations,
                funds,
                gas_funds: funds * (settings.gas_allocation/ 10000),
                settings
            }
        );

        mira_account.total_funds_invested = mira_account.total_funds_invested + funds;

        coin::transfer<AptosCoin>(manager, signer::address_of(&pool_signer), amount + deposit_fee);

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
                founded: created,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun add_gas_funds_to_pool(manager: &signer, pool_name: vector<u8>, gas_funds: u64) acquires MiraAccount, MiraPool {
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        coin::transfer<AptosCoin>(manager, address_of(&pool_signer), gas_funds);
        owner.funds_on_gas = owner.funds_on_gas + gas_funds;
        mira_pool.gas_funds = mira_pool.gas_funds + gas_funds;
    }

    public entry fun withdraw_gas_funds_from_pool(manager: &signer, pool_name: vector<u8>, gas_funds: u64) acquires MiraAccount, MiraPool {
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        assert!(gas_funds <= mira_pool.gas_funds, INVALID_PARAMETER);

        coin::transfer<AptosCoin>(&pool_signer, address_of(manager), gas_funds);
        owner.funds_on_gas = owner.funds_on_gas - gas_funds;
        mira_pool.gas_funds = mira_pool.gas_funds - gas_funds;
    }

    public entry fun repossess(admin: &signer, user: address, pool_name: vector<u8>) acquires MiraPool, MiraAccount {
        let admin_addr = address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        let owner = borrow_global_mut<MiraAccount>(user);
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);

        let pool = move_from<MiraPool>(address_of(&pool_signer));
        move_to<MiraPool>(admin, pool);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(admin));

        mira_pool.settings.management_fee = 10;
        mira_pool.manager = address_of(admin);

        owner.funds_under_management = owner.funds_under_management - mira_pool.funds;
        let mira = borrow_global_mut<MiraAccount>(address_of(admin));
        mira.funds_under_management = mira.funds_under_management + mira_pool.funds;
    }


    public entry fun auto_rebalance(manager: &signer, pool_name: vector<u8>)acquires MiraAccount, MiraPool {
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        let i = 0;

        while (i < table_with_length::length(&mira_pool.token_allocations)) {
            let _token = *table_with_length::borrow(&mira_pool.tokens, i);
            let _token_allocation = *table_with_length::borrow(&mira_pool.tokens, i);
            // find amounts in pool
            // if amounts off by > 1%, swap + or -
            i = i + 1;
        };
    }

    public entry fun invest(investor: &signer, pool_name: vector<u8>, pool_owner: address, amount: u64) acquires MiraPool, MiraAccount, MiraStatus {
        assert!(amount>0, INSUFFICIENT_FUNDS);

        let investor_addr = address_of(investor);
        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let pool_signer_capability = table::borrow_mut<String, SignerCapability>( &mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        let curramount = 0;
        if (table_with_length::contains(&mut mira_pool.investors, investor_addr)) {
            curramount = *table_with_length::borrow(&mira_pool.investors, investor_addr);
        };

        table::upsert(&mut mira_pool.investors, investor_addr, curramount + amount);
        mira_pool.amount = mira_pool.amount + amount;

        coin::transfer<AptosCoin>(investor, signer::address_of(&pool_signer), amount);

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        //emit deposit
        event::emit_event<MiraPoolDepositEvent>(
            &mut miraStatus.deposit_pool_events,
            MiraPoolDepositEvent{
                pool_name: string::utf8(pool_name),
                investor: investor_addr,
                amount,
                timestamp: timestamp::now_seconds()
            }
        );

        // //BTC
        // let btc_percent =table::borrow(&mira_pool.index_allocation, string::utf8(b"BTC"));

        coin::transfer<AptosCoin>(investor, address_of(&pool_signer), amount);

        //BTC
        //let btc_percent =table::borrow(&mira_pool.index_allocation, string::utf8(b"BTC"));
        //let btc_amount = amount * (*btc_percent as u64) / 100;
        //swap_aptos(investor, btc_amount, 0);

        // //USDT
        // let usdt_percent =table::borrow(&mira_pool.index_allocation, string::utf8(b"USDT"));
        // let usdt_amount = amount * (*usdt_percent as u64) /100;

        // let aptos_coins_to_swap_usdt = coin::withdraw<AptosCoin>(investor, usdt_amount);
        // let usdt_amount_to_get = router::get_amount_out<AptosCoin, BTC, LP<AptosCoin, USDT>>(
        //     @liquidswap,
        //     usdt_amount
        // );
        // let usdt = router::swap_exact_coin_for_coin<AptosCoin, BTC, LP<AptosCoin, USDT>>(
        //     @liquidswap,
        //     aptos_coins_to_swap_usdt,
        //     usdt_amount_to_get
        // );
        // coin::deposit(signer::address_of(&pool_signer), usdt);
    }

    public entry fun swap_aptos(account: &signer, amount: u64, min_value_to_get: u64) {
        let aptos_amount_to_swap = amount;
        let aptos_coins_to_swap = coin::withdraw<AptosCoin>(account, aptos_amount_to_swap);

        let btc = router::swap_exact_coin_for_coin<AptosCoin, BTC, Uncorrelated>(
            aptos_coins_to_swap,
            min_value_to_get
        );

        let account_addr = address_of(account);

        // Register BTC coin on account in case the account don't have it.
        if (!coin::is_account_registered<BTC>(account_addr)) {
            coin::register<BTC>(account);
        };

        // Deposit on account.
        coin::deposit(account_addr, btc);
    }

    public entry fun buy_btc(account: &signer, btc_min_value_to_get: u64) {
        let aptos_amount_to_swap = 1000;
        let aptos_coins_to_swap = coin::withdraw<AptosCoin>(account, aptos_amount_to_swap);

        let btc = router::swap_exact_coin_for_coin<AptosCoin, BTC, Uncorrelated>(
            aptos_coins_to_swap,
            btc_min_value_to_get
        );

        let account_addr = signer::address_of(account);

        // Register BTC coin on account in case the account don't have it.
        if (!coin::is_account_registered<BTC>(account_addr)) {
            coin::register<BTC>(account);
        };

        // Deposit on account.
        coin::deposit(account_addr, btc);
    }

    public entry fun withdraw(investor: &signer, pool_name: vector<u8>, pool_owner: address, amount: u64) acquires MiraPool, MiraAccount, MiraStatus {
        let investor_addr = signer::address_of(investor);
        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let pool_signer_capability = table::borrow_mut<String, SignerCapability>( &mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        let withdrawal_limit = table::borrow(&mut mira_pool.investors, investor_addr);
        assert!(*withdrawal_limit >= amount, INSUFFICIENT_FUNDS);

        mira_pool.amount = mira_pool.amount - amount;
        coin::transfer<AptosCoin>(&pool_signer, investor_addr, amount);
        table::upsert(&mut mira_pool.investors, investor_addr, *withdrawal_limit - amount);

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        //emit deposit
        event::emit_event<MiraPoolWithdrawEvent>(
            &mut miraStatus.withdraw_pool_events,
            MiraPoolWithdrawEvent{
                pool_name: string::utf8(pool_name),
                investor: investor_addr,
                amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }
}
