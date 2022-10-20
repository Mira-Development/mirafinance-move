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
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account::SignerCapability;
    use std::signer::{Self, address_of};
    use aptos_std::table_with_length::{Self, TableWithLength};

    #[test_only]
    use aptos_std::debug;

    const MODULE_ADMIN: address = @mira;

    //error codes
    const INVALID_ADMIN_ADDRESS: u64 = 1;
    const INVALID_ACCOUNT_NAME: u64 = 2;
    const INSUFFICIENT_FUNDS: u64 = 3;
    const INVALID_PARAMETER: u64 = 4;
    const DUPLICATE_NAME: u64 = 5;
    const NO_REACHED_WITHDRAWAL_TIME:u64 = 6;

    const FEE_DECIMAL:u64 = 10000;
    const MAX_MANAGEMENT_FEE:u64 = 5000; //50%
    const MIN_CONTRIBUTION:u64 = 100000000;  //1APT
    const MAX_DAYS:u64 = 730;
    const SEC_OF_DAY:u64 = 86400;
    const MAX_REBALANCING_TIMES:u64 = 4;
    const MIN_INPUT_AMOUNT:u64 = 10000; // Octas

    const PUBLIC_ALLOCATION:u8 = 0;
    const PRIVATE_ALLOCATION:u8 = 1;
    const PRIVATE_FUND:u8 = 2;

    struct MiraStatus has key {
        create_pool_events: EventHandle<MiraPoolCreateEvent>,
        update_pool_events: EventHandle<MiraPoolUpdateEvent>,
        deposit_pool_events: EventHandle<MiraPoolDepositEvent>,
        withdraw_pool_events: EventHandle<MiraPoolWithdrawEvent>
    }

    struct MiraPool has key, store {
        pool_name: String,
        created: u64, //in seconds
        pool_address: address,
        manager_addr: address,
        rebalancing_gas: u64,  // unit: Otas, for gas fee to call rebalance..  only change by pool manager.
        investors: TableWithLength<address, u64>,
        index_allocation: vector<u64>, // list of index allocation
        index_list: vector<String>, // list of index_name
        amount: u64,
        gas_pool: u64,
        settings: MiraPoolSettings
    }

    struct MiraPoolSettings has store, copy, drop {
        management_fee: u64,
        rebalancing_period: u64,
        minimum_contribution: u64,
        minimum_withdrawal_period: u64,
        referral_reward: u64,
        privacy_allocation: u8
    }

    struct MiraAccount has key {
        owner: address,
        account_name: String,
        total_funds_invested: u64,
        funds_under_management: u64,
        funds_on_gas: u64,
        funds_on_management: u64,
        created_pools: TableWithLength<String, SignerCapability>,
        invested_pools: TableWithLength<String, SignerCapability>
    }
    struct MiraUserWithdraw has key{
        last_withdraw_timestamp: SimpleMap<address, u64> // map of pool_addr, last_timestamp
    }

    //emit during creating pool
    struct MiraPoolCreateEvent has store, drop {
        pool_name: String,
        pool_owner: address,
        pool_address: address,
        privacy_allocation: u8,
        management_fee: u64,
        founded: u64,
        timestamp: u64
    }
    struct MiraPoolUpdateEvent has store, drop{
        pool_name: String,
        pool_owner: address,
        pool_address: address,
        privacy_allocation: u8,
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

    public entry fun init_mira(admin: &signer){
        let admin_addr = address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        move_to(admin, MiraStatus{
            create_pool_events: account::new_event_handle<MiraPoolCreateEvent>(admin),
            update_pool_events: account::new_event_handle<MiraPoolUpdateEvent>(admin),
            deposit_pool_events: account::new_event_handle<MiraPoolDepositEvent>(admin),
	        withdraw_pool_events: account::new_event_handle<MiraPoolWithdrawEvent>(admin)
        });
    }

    public entry fun connect_account(
        user: &signer,
        account_name: vector<u8>
    ){
        let user_addr = address_of(user);
        if ( !exists<MiraAccount>(user_addr) ) {
            move_to(user, MiraAccount {
                owner: user_addr,
                account_name: string::utf8(account_name),
                total_funds_invested: 0,
                funds_under_management: 0,
                funds_on_gas: 0,
                funds_on_management: 0,
                created_pools: table_with_length::new<String, SignerCapability>(),
                invested_pools: table_with_length::new<String, SignerCapability>()
            })
        };
    }

    fun create_pool_settings(
        management_fee: u64,
        rebalancing_period: u64,
        minimum_contribution: u64,
        minimum_withdrawal_period: u64,
        referral_reward: u64,
        privacy_allocation: u8,
    ):MiraPoolSettings {
        MiraPoolSettings {
            management_fee, rebalancing_period, minimum_contribution, minimum_withdrawal_period, referral_reward, privacy_allocation
        }
    }

    // this should happen on backend, shouldn't charge user gas to change account name
    public entry fun change_account_name(
        user: &signer,
        name: vector<u8>
    ) acquires MiraAccount
    {
        assert!(vector::length(&name) >0, INVALID_ACCOUNT_NAME);
        let mira_acct = borrow_global_mut<MiraAccount>(address_of(user));
        mira_acct.account_name = string::utf8(name);
    }

    public entry fun create_pool(
        manager: &signer,
        pool_name: vector<u8>,
        amount: u64,
        gas_amount: u64,
        management_fee: u64,
        rebalancing_period: u64, // in days (0 - 730)
        rebalancing_gas: u64,
        minimum_contribution: u64,
        minimum_withdrawal_period: u64, // in days (0 - 730)
        referral_reward: u64,
        index_allocation_key: vector<String>,
        index_allocation_value: vector<u64>,
        privacy_allocation: u8,
    ) acquires MiraAccount, MiraStatus
    {
        let manager_addr = address_of(manager);
        let mira_account = borrow_global_mut<MiraAccount>(manager_addr);

        assert!(!table_with_length::contains(&mut mira_account.created_pools, string::utf8(pool_name)), DUPLICATE_NAME);
        // check that pool_name is unique
        assert!(!string::is_empty(&string::utf8(pool_name)), INVALID_PARAMETER);
        assert!(amount >= MIN_INPUT_AMOUNT, INSUFFICIENT_FUNDS);
        assert!(gas_amount >= MIN_INPUT_AMOUNT, INSUFFICIENT_FUNDS);
        assert! ( vector::length(&index_allocation_key) == vector::length(&index_allocation_value), INVALID_PARAMETER);
        assert!(management_fee <= MAX_MANAGEMENT_FEE, INVALID_PARAMETER);
        assert!(minimum_contribution <= MIN_CONTRIBUTION, INVALID_PARAMETER);
        assert!(privacy_allocation >=0 && privacy_allocation <3, INVALID_PARAMETER);
        assert!(minimum_withdrawal_period <= MAX_DAYS, INVALID_PARAMETER);
        assert!(rebalancing_gas>=MIN_INPUT_AMOUNT, INSUFFICIENT_FUNDS);  //min 10000 Otas

        let (pool_signer, pool_signer_capability) = account::create_resource_account(manager, pool_name);
        coin::register<AptosCoin>(&pool_signer);

        let settings = create_pool_settings( management_fee, rebalancing_period, minimum_contribution, minimum_withdrawal_period, referral_reward, privacy_allocation);

        let investors = table_with_length::new<address, u64>();
        table_with_length::add(&mut investors, manager_addr, amount);

        let sum_allocation:u64 = 0;
        let i = 0;
        while (i < vector::length(&index_allocation_key)){
            let index_alloc_value:u64 = *vector::borrow(&index_allocation_value, i);
            assert!(!string::is_empty(vector::borrow(&index_allocation_key, i)), INVALID_PARAMETER);
            assert!(index_alloc_value < 100, INVALID_PARAMETER);
            i = i + 1;
            sum_allocation = sum_allocation + index_alloc_value;
        };
        assert!(sum_allocation == 100, INVALID_PARAMETER);

        let created = timestamp::now_seconds();
        move_to(&pool_signer,
            MiraPool {
                pool_name: string::utf8(pool_name),
                pool_address: address_of(&pool_signer),
                manager_addr,
                created,
                investors,
                index_list: index_allocation_key,
                index_allocation: index_allocation_value,
                amount,
                gas_pool: gas_amount,
                rebalancing_gas,
                settings
            }
        );

        mira_account.total_funds_invested = mira_account.total_funds_invested + amount;

        coin::transfer<AptosCoin>(manager, signer::address_of(&pool_signer), amount + gas_amount);

        table_with_length::add(&mut mira_account.created_pools, string::utf8(pool_name), pool_signer_capability);

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        event::emit_event<MiraPoolCreateEvent>(
            &mut miraStatus.create_pool_events,
            MiraPoolCreateEvent{
                pool_name: string::utf8(pool_name),
                pool_owner: manager_addr,
                pool_address: signer::address_of(&pool_signer),
                privacy_allocation,
                management_fee,
                founded: created,
                timestamp: timestamp::now_seconds()
            }
        )
    }
    //Update rebalancing_gas fee for Pool
    public entry fun update_rebalancing_gas(
        manager: &signer,
        pool_name: vector<u8>,
        amount: u64
    )acquires MiraPool, MiraAccount
    {
        assert!(amount>=MIN_INPUT_AMOUNT, INSUFFICIENT_FUNDS);  //min 1000 Otas
        let pool_name_str = string::utf8(pool_name);
        assert!(!string::is_empty(&pool_name_str), INVALID_PARAMETER);
        let manager_addr = address_of(manager);

        let mira_account = borrow_global_mut<MiraAccount>(manager_addr);
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(
             &mut mira_account.created_pools,
             copy pool_name_str
        );
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let pool_signer_addr = address_of(&pool_signer);
        let mira_pool = borrow_global_mut<MiraPool>(pool_signer_addr);
        mira_pool.rebalancing_gas = amount;
    }

    public entry fun update_pool(
        manager: &signer,
        pool_name: vector<u8>,
        rebalancing_period: u64,
        minimum_contribution: u64,
        minimum_withdrawal_period: u64,
        referral_reward: u64,
        index_allocation_key: vector<String>,
        index_allocation_value: vector<u64>,
        privacy_allocation: u8,
    )acquires MiraAccount, MiraStatus, MiraPool
    {
        // check that pool_name is unique
        let pool_name_str = string::utf8(pool_name);
        assert!(!string::is_empty(&pool_name_str), INVALID_PARAMETER);
        assert! ( vector::length(&index_allocation_key) == vector::length(&index_allocation_value), INVALID_PARAMETER);
        assert!(minimum_contribution <= MIN_CONTRIBUTION, INVALID_PARAMETER);
        assert!(privacy_allocation >= 0 && privacy_allocation < 3, INVALID_PARAMETER);
        assert!(minimum_withdrawal_period <= MAX_DAYS, INVALID_PARAMETER);

        let manager_addr = address_of(manager);
        let mira_account = borrow_global_mut<MiraAccount>(manager_addr);
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(
             &mut mira_account.created_pools,
             copy pool_name_str
        );
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let pool_signer_addr = address_of(&pool_signer);
        let mira_pool = borrow_global_mut<MiraPool>(pool_signer_addr);
        let sum_allocation:u64 = 0;
        let i = 0;
        while (i < vector::length(&index_allocation_key)){
            let index_alloc_value:u64 = *vector::borrow(&index_allocation_value, i);
            assert!(!string::is_empty(vector::borrow(&index_allocation_key, i)), INVALID_PARAMETER);
            assert!(index_alloc_value < 100, INVALID_PARAMETER);
            i = i + 1;
            sum_allocation = sum_allocation + index_alloc_value;
        };
        assert!(sum_allocation == 100, INVALID_PARAMETER);
        mira_pool.settings.rebalancing_period = rebalancing_period;
        mira_pool.settings.minimum_contribution = minimum_contribution;
        mira_pool.settings.minimum_withdrawal_period = minimum_withdrawal_period;
        mira_pool.settings.referral_reward = referral_reward;
        mira_pool.settings.privacy_allocation = privacy_allocation;

        mira_pool.index_allocation = index_allocation_value;

        mira_pool.index_list = index_allocation_key;

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        event::emit_event<MiraPoolUpdateEvent>(
            &mut miraStatus.update_pool_events,
            MiraPoolUpdateEvent{
                pool_name: pool_name_str,
                pool_owner: manager_addr,
                pool_address: pool_signer_addr,
                privacy_allocation,
                timestamp: timestamp::now_seconds()
            }
        )
    }

    public entry fun add_to_gas_pool(
        manager: &signer,
        pool_name: vector<u8>,
        amount: u64
    )acquires MiraAccount, MiraPool
    {
        assert!(amount> MIN_INPUT_AMOUNT, INSUFFICIENT_FUNDS);
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        coin::transfer<AptosCoin>(manager, address_of(&pool_signer), amount);
        owner.funds_on_gas = owner.funds_on_gas +amount;
        mira_pool.gas_pool = mira_pool.gas_pool + amount;
    }

    public entry fun withdraw_from_gas_pool(
        manager: &signer,
        pool_name: vector<u8>,
        amount: u64
    )acquires MiraAccount, MiraPool
    {
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        assert!( amount >0, INVALID_PARAMETER);
        assert!( amount <= mira_pool.gas_pool, INSUFFICIENT_FUNDS);
        assert!( amount <= owner.funds_on_gas, INSUFFICIENT_FUNDS);

        coin::transfer<AptosCoin>( &pool_signer, address_of(manager), amount );
        owner.funds_on_gas = owner.funds_on_gas - amount;
        mira_pool.gas_pool = mira_pool.gas_pool - amount;
    }

    //Move Pool from owner to Admin
    public entry fun repossess(
        admin: &signer,
        user: address,pool_name: vector<u8>
    )acquires MiraPool, MiraAccount
    {
        let admin_addr = address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        let owner = borrow_global_mut<MiraAccount>(user);
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);

        let pool = move_from<MiraPool>(address_of(&pool_signer));
        move_to<MiraPool>(admin, pool);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(admin));

        mira_pool.settings.management_fee = 10;
        mira_pool.manager_addr = admin_addr;

        owner.funds_under_management = owner.funds_under_management - mira_pool.amount;
        owner.funds_on_gas = owner.funds_on_gas - mira_pool.gas_pool;
        let mira = borrow_global_mut<MiraAccount>(admin_addr);
        mira.funds_under_management = mira.funds_under_management + mira_pool.amount;
        mira.funds_on_gas = mira.funds_on_gas + mira_pool.gas_pool;
    }

    public entry fun auto_rebalance(manager: &signer, pool_name: vector<u8>)acquires MiraAccount, MiraPool {
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(&mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let _mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        let _i = 0;

        // while (i < vector::length(&mira_pool.index_list)) {
        //     let index_name = vector::borrow(&mira_pool.index_list, i);
        //     let index_allocation = *table_with_length::borrow(&mira_pool.index_allocation, *index_name);
        //     // find amounts in pool
        //     // if amounts off by > 1%, swap + or -
        //     i = i + 1;
        // };
    }

    public entry fun invest(
        investor: &signer,
        pool_name: vector<u8>,
        pool_owner: address,
        amount: u64
    )acquires MiraPool, MiraAccount, MiraStatus, MiraUserWithdraw
    {
        assert!(amount>MIN_INPUT_AMOUNT, INSUFFICIENT_FUNDS);
        let investor_addr = address_of(investor);
        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>( &mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        let management_fee = mira_pool.settings.management_fee;
        let fee_amount = ( (amount as u128)* (management_fee as u128) / (FEE_DECIMAL as u128) as u64);
        if (table_with_length::contains(&mira_pool.investors, investor_addr)) {
            let mut_curramount = table_with_length::borrow_mut(&mut mira_pool.investors, investor_addr);
            *mut_curramount = *mut_curramount + amount - fee_amount ;
        }else{
            table_with_length::add(&mut mira_pool.investors, investor_addr, amount - fee_amount);
        };

        if (fee_amount > 0){
            let mut_manager_amount = table_with_length::borrow_mut(&mut mira_pool.investors, mira_pool.manager_addr);
            *mut_manager_amount = *mut_manager_amount + fee_amount;
        };

        mira_pool.amount = mira_pool.amount + amount;
        // process for rebalancing_gas
        let rebalancing_gas_fee = mira_pool.rebalancing_gas * MAX_REBALANCING_TIMES;
        mira_pool.gas_pool = mira_pool.gas_pool + rebalancing_gas_fee;
        owner.funds_on_gas = owner.funds_on_gas + rebalancing_gas_fee;

        coin::transfer<AptosCoin>(investor, address_of(&pool_signer), amount + rebalancing_gas_fee);

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        let now = timestamp::now_seconds();
        //emit deposit
        event::emit_event<MiraPoolDepositEvent>(
            &mut miraStatus.deposit_pool_events,
            MiraPoolDepositEvent{
                pool_name: string::utf8(pool_name),
                investor: investor_addr,
                amount: amount - fee_amount,
                timestamp: now
            }
        );
        let pool_addr = address_of(&pool_signer);
        if (!exists<MiraUserWithdraw>(investor_addr)){
            let last_withdraw_timestamp = simple_map::create<address, u64>();
            simple_map::add(&mut last_withdraw_timestamp, pool_addr, now);
            move_to(investor, MiraUserWithdraw{
                last_withdraw_timestamp
            });
        }else{
            let mira_user_withdraw_status = borrow_global_mut<MiraUserWithdraw>(investor_addr);
            if ( simple_map::contains_key( &mira_user_withdraw_status.last_withdraw_timestamp, &pool_addr)){
                let value = simple_map::borrow_mut(&mut mira_user_withdraw_status.last_withdraw_timestamp, &pool_addr);
                *value = now;
            }else{
                simple_map::add(&mut mira_user_withdraw_status.last_withdraw_timestamp, pool_addr, now);
            };
        };

        // //BTC
        // let btc_percent =table::borrow(&mira_pool.index_allocation, string::utf8(b"BTC"));

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

    public entry fun withdraw(
        investor: &signer,
        pool_name: vector<u8>,
        pool_owner: address,
        amount: u64
    )acquires MiraPool, MiraAccount, MiraStatus, MiraUserWithdraw
    {
        let investor_addr = address_of(investor);
        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>( &mut owner.created_pools, string::utf8(pool_name));
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        let pool_addr = address_of(&pool_signer);

        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        let withdrawal_limit = table_with_length::borrow_mut(&mut mira_pool.investors, investor_addr);
        assert!(*withdrawal_limit >= amount, INSUFFICIENT_FUNDS);
        let user_withdraw_status = borrow_global_mut<MiraUserWithdraw>(investor_addr);
        let now = timestamp::now_seconds();
        let last_timestamp = simple_map::borrow_mut<address, u64>(&mut user_withdraw_status.last_withdraw_timestamp, &pool_addr);

        if (mira_pool.settings.minimum_withdrawal_period > 0){
            assert!( *last_timestamp + mira_pool.settings.minimum_withdrawal_period * SEC_OF_DAY < now, NO_REACHED_WITHDRAWAL_TIME);
        }else{
            *last_timestamp = now;
        };


        mira_pool.amount = mira_pool.amount - amount;
        coin::transfer<AptosCoin>(&pool_signer, investor_addr, amount);
        *withdrawal_limit = *withdrawal_limit - amount;

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

    #[test_only]
    public fun print_pool_info(user: &signer, pool_name: String) acquires MiraAccount, MiraPool {
        let acct = borrow_global_mut<MiraAccount>(address_of(user));
        let signercap = table_with_length::borrow(&acct.created_pools, pool_name);
        let pool_signer = account::create_signer_with_capability(signercap);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        debug::print(mira_pool);
    }
    #[test_only]
    public fun print_account_info(user: &signer)acquires MiraAccount {
        let acct = borrow_global_mut<MiraAccount>(address_of(user));
        debug::print(acct);
    }
}
