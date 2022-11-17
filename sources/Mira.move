module mira::mira {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::event::{Self, EventHandle};
    // use aptos_framework::timestamp;
    use std::string::String;
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account::SignerCapability;
    use std::signer::{Self, address_of};
    use aptos_std::table_with_length::{Self, TableWithLength};
    // use liquidswap::curves::Uncorrelated;
    use aptos_std::table;
    use mira::coins::{BTC, ETH, SOL, USDC, APT};
    // use liquidswap::router_v2;
    use aptos_std::table::Table;
    use mira::iterable_table::{IterableTable, head_key, borrow_iter, borrow};
    use mira::iterable_table;
    use std::option;

    #[test_only]
    use aptos_framework::coin::balance;
    use aptos_std::debug;
    use aptos_framework::coin::{symbol, transfer};
    // use mira::math;

    const MODULE_ADMIN: address = @mira;

    //error codes
    const INVALID_ADMIN_ADDRESS: u64 = 1;
    const INVALID_ACCOUNT_NAME: u64 = 2;
    const INSUFFICIENT_FUNDS: u64 = 3;
    const INVALID_PARAMETER: u64 = 4;
    const DUPLICATE_NAME: u64 = 5;
    const WITHDRAWAL_PERIOD_NOT_REACHED: u64 = 6;
    const CANNOT_UPDATE_MANAGEMENT_FEE: u64 = 7;
    const NO_REBALANCE_PERMISSION: u64 = 8;
    const WITHDRAWALS_LOCKED_FOR_USER_SAFETY: u64 = 9;
    const USER_MUST_REGISTER_THIS_TOKEN: u64 = 10;
    const NO_FUNDS_LEFT: u64 = 11;
    const ROUNDING_ERROR: u64 = 12;
    const CREATE_MIRA_ACCOUNT: u64 = 13;

    // parameters
    const MAX_MANAGEMENT_FEE: u64 = 1000000000;
    // 10.00000000%
    const GLOBAL_MIN_CONTRIBUTION: u64 = 100000000;
    // $APT 1.00000000
    const TOTAL_INVESTOR_STAKE: u64 = 10000000000;
    // 100.00000000%
    const MAX_DAYS: u64 = 730;
    const SEC_OF_DAY: u64 = 86400;
    const MAX_REBALANCING_TIMES: u64 = 4;
    const PUBLIC_ALLOCATION: u8 = 0;
    const PRIVATE_ALLOCATION: u8 = 1;
    const PRIVATE_FUND: u8 = 2;

    //defaults
    const DEFAULT_TRADING_TOKEN: vector<u8> = b"APT";
    const DEFAULT_GAS_ALLOCATION: u64 = 5000000;
    // $APT 0.0500000;
    const UNIT_DECIMAL: u64 = 100000000;
    const VALID_TOKENS: vector<vector<u8>> = vector<vector<u8>>[b"APT", b"USDC", b"BTC", b"ETH", b"SOL"];

    // to keep dApp updated
    struct MiraStatus has key {
        create_pool_events: EventHandle<MiraPoolCreateEvent>,
        update_pool_events: EventHandle<MiraPoolUpdateEvent>,
        deposit_pool_events: EventHandle<MiraPoolDepositEvent>,
        withdraw_pool_events: EventHandle<MiraPoolWithdrawEvent>
    }

    // where funds are stored
    struct MiraPool has key, store {
        pool_name: String,
        time_created: u64,
        //in seconds
        pool_address: address,
        // address of resource signer account that owns the pool
        manager_addr: address,
        investors: IterableTable<address, u64>,
        // map of investor's address and amount
        token_allocations: vector<u64>,
        // list of index allocation
        token_names: vector<vector<u8>>,
        // list of index_name
        investor_funds: u64,
        //total_amount
        gas_funds: u64,
        //amount for gas
        management_fee: u64,
        // percentage of investments that are allocated from investors to manager each year
        // for example: management fee set at 1% - newuser invests $100; first year, 1% of newuser's ownership of
        // pool is transferred to manager (equivalent of $1.00), next year, 0.99% (equivalent of $0.99)
        rebalancing_period: u64,
        // how often rebalancing is scheduled (0 - 730 days)
        minimum_contribution: u64,
        // minimum amount an investor can contribute to the portfolio (0 - 730 days)
        minimum_withdrawal_period: u64,
        // minimum amount of time before an investor can withdraw their funds from the portfolio
        referral_reward: u64,
        // percentage of management fee earnings that will be spent on referral rewards
        // for example: referral reward set at 10%, and management fee at 1%
        // user recruits a new investor, who invests $100 - manager now earns 0.9% on their investment, and user 0.1%
        // first year, manager earns $0.90, user earns $0.10, and so on
        privacy_allocation: u8,
        // 1, public: any user can see portfolio on leaderboard
        // 2, private distribution: like public, except token allocation is hidden unless user has invested
        // 3, hidden: portfolios don't show up on site, can only be viewed when special link is shared
        gas_allocation: u64,
        // percentage of manager's investment that is set aside for rebalancing costs
        whitelist: Table<u64, address>,
        // only users who are on the whitelist can invest in the portfolio
        rebalance_on_investment: u8 // determines whether a new user investing auto-rebalances the portfolio (incorporating rebalance into their gas cost)
        // if this is on, it also means that any user can rebalance the portfolio themselves at any time through the contract.
    }

    // user account
    struct MiraAccount has key {
        addr: address,
        account_name: String,
        total_funds_invested: u64,
        funds_under_management: u64,
        funds_on_gas: u64,
        funds_on_management: u64,
        created_pools: TableWithLength<String, SignerCapability>,
        invested_pools: TableWithLength<String, SignerCapability>
    }

    struct MiraUserWithdraw has key {
        last_withdraw_timestamp: SimpleMap<address, u64> // map of pool_addr, last_timestamp
    }

    struct MiraPoolCreateEvent has store, drop {
        pool_name: String,
        pool_owner: address,
        pool_address: address,
        privacy_allocation: u8,
        management_fee: u64,
        founded: u64,
        timestamp: u64
    }

    struct MiraPoolUpdateEvent has store, drop {
        pool_name: String,
        pool_owner: address,
        pool_address: address,
        privacy_allocation: u8,
        timestamp: u64
    }

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

    struct LockWithdrawals has key {
        lock: u8
    }

    struct MiraFees has key {
        creation: u64,
        investment: u64,
        management: u64
    }

    public entry fun init_mira(admin: &signer) {
        let admin_addr = address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        move_to(admin, MiraStatus {
            create_pool_events: account::new_event_handle<MiraPoolCreateEvent>(admin),
            update_pool_events: account::new_event_handle<MiraPoolUpdateEvent>(admin),
            deposit_pool_events: account::new_event_handle<MiraPoolDepositEvent>(admin),
            withdraw_pool_events: account::new_event_handle<MiraPoolWithdrawEvent>(admin)
        });

        move_to(admin, LockWithdrawals {
            lock: 0
        });

        move_to(admin, MiraFees{
            creation: 0,
            investment: 0,
            management: 0
        });

        connect_account(admin, b"mira_admin");
    }

    public entry fun connect_account(
        user: &signer,
        account_name: vector<u8>
    ) {
        let user_addr = address_of(user);
        if (!exists<MiraAccount>(user_addr)) {
            move_to(user, MiraAccount {
                addr: user_addr,
                account_name: string::utf8(account_name),
                total_funds_invested: 0,
                funds_under_management: 0,
                funds_on_gas: 0,
                funds_on_management: 0,
                created_pools: table_with_length::new<String, SignerCapability>(),
                invested_pools: table_with_length::new<String, SignerCapability>()
            });
            register_coin<APT>(user);
            register_coin<USDC>(user);
            register_coin<BTC>(user);
            register_coin<ETH>(user);
            register_coin<SOL>(user);
        };
    }

    // this should happen on backend, shouldn't charge user gas to change account name
    public entry fun change_account_name(
        user: &signer,
        name: vector<u8>
    ) acquires MiraAccount
    {
        assert!(vector::length(&name) > 0, INVALID_ACCOUNT_NAME);
        let mira_acct = borrow_global_mut<MiraAccount>(address_of(user));
        mira_acct.account_name = string::utf8(name);
    }

    public entry fun send_funds_to_user<CoinX>(sender: &signer, recipient: address, amount: u64) {
        assert!(coin::is_account_registered<CoinX>(recipient), USER_MUST_REGISTER_THIS_TOKEN);
        coin::transfer<CoinX>(sender, recipient, amount);
    }

    // create a portfolio
    public entry fun create_pool<CoinX>(
        manager: &signer,
        pool_name: vector<u8>,
        token_names: vector<vector<u8>>,
        token_allocations: vector<u64>,
        deposit_amount: u64,
        management_fee: u64,
        minimum_contribution: u64,
        rebalancing_period: u64, // in days (0 - 730)
        rebalance_on_investment: u8,
        gas: option::Option<u64>
    ) acquires MiraAccount, MiraStatus, MiraFees
    {
        let manager_addr = address_of(manager);
        assert!(exists<MiraAccount>(manager_addr),
            CREATE_MIRA_ACCOUNT
        ); // in the future, auto-create account with random username

        let creation_fee = borrow_global_mut<MiraFees>(MODULE_ADMIN).creation;
        deposit_amount = deposit_amount * (TOTAL_INVESTOR_STAKE -  creation_fee)/ TOTAL_INVESTOR_STAKE;
        transfer<CoinX>(manager, MODULE_ADMIN, (deposit_amount * creation_fee) / TOTAL_INVESTOR_STAKE);

        let mira_account = borrow_global_mut<MiraAccount>(manager_addr);
        if (minimum_contribution < GLOBAL_MIN_CONTRIBUTION) { minimum_contribution = GLOBAL_MIN_CONTRIBUTION };
        let gas_allocation = DEFAULT_GAS_ALLOCATION;
        if (!option::is_none(&gas)) { gas_allocation = *option::borrow(&gas); };

        // all of these values will be modifiable in next update
        let minimum_withdrawal_period = 0;
        let privacy_allocation = PUBLIC_ALLOCATION;
        let referral_reward = 0;
        let whitelist = table::new<u64, address>();

        // clean inputs for pool name, investment amount, & management fee
        assert!(!string::is_empty(&string::utf8(pool_name)), INVALID_PARAMETER);
        assert!(!table_with_length::contains(&mut mira_account.created_pools, string::utf8(pool_name)), DUPLICATE_NAME);
        assert!(
            deposit_amount >= (GLOBAL_MIN_CONTRIBUTION / UNIT_DECIMAL) * (get_exchange_rate<USDC, CoinX>(
            ) / UNIT_DECIMAL),
            INSUFFICIENT_FUNDS
        );
        assert!(
            deposit_amount >= (minimum_contribution / UNIT_DECIMAL) * (get_exchange_rate<USDC, CoinX>() / UNIT_DECIMAL),
            INSUFFICIENT_FUNDS
        );
        assert!(vector::length(&token_names) == vector::length(&token_allocations), INVALID_PARAMETER);
        assert!(management_fee <= MAX_MANAGEMENT_FEE, INVALID_PARAMETER);

        // in next update, clean inputs for min withdrawal, min contribution, privacy allocation, and gas percentage

        let (pool_signer, pool_signer_capability) = account::create_resource_account(manager, pool_name);
        // register all tokens that are traded here, so that users don't need to have tokens registered in their wallet to have stake in them
        coin::register<APT>(&pool_signer);
        coin::register<USDC>(&pool_signer);
        coin::register<BTC>(&pool_signer);
        coin::register<ETH>(&pool_signer);
        coin::register<SOL>(&pool_signer);

        let investors = iterable_table::new<address, u64>();
        iterable_table::add(
            &mut investors,
            manager_addr,
            TOTAL_INVESTOR_STAKE
        ); // keep track of investor stake as a percentage
        iterable_table::add(
            &mut investors,
            MODULE_ADMIN,
            0
        ); // add mira

        check_tokens(token_names, token_allocations);

        // should set based on number of rebalances, and in UI: we recommend setting aside $0.50 for gas - this should suffice for the next 2 years of rebalances.
        let gas_funds = gas_allocation;
        let investor_funds = deposit_amount - gas_funds;

        let created = 0; //bug with timestamp::now_seconds()
        move_to(&pool_signer,
            MiraPool {
                pool_name: string::utf8(pool_name),
                time_created: created,
                pool_address: address_of(&pool_signer),
                manager_addr,
                investors,
                token_allocations,
                token_names,
                investor_funds,
                gas_funds,
                management_fee,
                rebalancing_period,
                minimum_contribution,
                minimum_withdrawal_period,
                referral_reward,
                privacy_allocation,
                gas_allocation,
                whitelist,
                rebalance_on_investment
            }
        );

        mira_account.total_funds_invested = mira_account.total_funds_invested + investor_funds;
        mira_account.funds_under_management = mira_account.funds_under_management + investor_funds;
        mira_account.funds_on_gas = mira_account.funds_on_gas + gas_funds;

        coin::transfer<CoinX>(manager, signer::address_of(&pool_signer), (investor_funds + gas_funds));

        table_with_length::add(&mut mira_account.created_pools, string::utf8(pool_name), pool_signer_capability);

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        event::emit_event<MiraPoolCreateEvent>(
            &mut miraStatus.create_pool_events,
            MiraPoolCreateEvent {
                pool_name: string::utf8(pool_name),
                pool_owner: manager_addr,
                pool_address: signer::address_of(&pool_signer),
                privacy_allocation,
                management_fee,
                founded: created,
                timestamp: 0 //bug with timestamp::now_seconds()
            }
        );
        // TODO: add MiraWithdraw so manager can invest in own fund
    }

    public entry fun update_pool(
        manager: &signer,
        pool_name: vector<u8>,
        token_names: vector<vector<u8>>,
        token_allocations: vector<u64>,
        management_fee: u64,
        rebalancing_period: u64,
        rebalance_on_investment: u8,
        minimum_contribution: u64,
        rebalance_now: u8,
        // referral_reward: u64,
        // whitelist: Table<u64, address>
    )acquires MiraAccount, MiraStatus, MiraPool
    {
        let manager_addr = address_of(manager);
        assert!(exists<MiraAccount>(manager_addr),
            CREATE_MIRA_ACCOUNT
        );
        let mira_account = borrow_global_mut<MiraAccount>(manager_addr);

        if (minimum_contribution < GLOBAL_MIN_CONTRIBUTION) { minimum_contribution = GLOBAL_MIN_CONTRIBUTION };

        // clean inputs for pool, tokens, management fee
        let pool_name_str = string::utf8(pool_name);
        assert!(!string::is_empty(&pool_name_str), INVALID_PARAMETER);
        assert!(table_with_length::contains(&mira_account.created_pools, pool_name_str), INVALID_PARAMETER);
        assert!(vector::length(&token_names) == vector::length(&token_allocations), INVALID_PARAMETER);
        assert!(management_fee < MAX_MANAGEMENT_FEE, INVALID_PARAMETER);

        // in next update, clean inputs for min contribution, referral reward, and gas percentage

        let pool_signer = get_pool_signer(address_of(manager), pool_name);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        if (!(manager_addr == MODULE_ADMIN)) {
            // only admin can increase management fee
            assert!(management_fee < mira_pool.management_fee, CANNOT_UPDATE_MANAGEMENT_FEE);
        };

        check_tokens(token_names, token_allocations);

        mira_pool.rebalancing_period = rebalancing_period;
        mira_pool.token_allocations = token_allocations;
        mira_pool.token_names = token_names;
        mira_pool.management_fee = management_fee;
        mira_pool.rebalance_on_investment = rebalance_on_investment;
        mira_pool.minimum_contribution = minimum_contribution;

        if(rebalance_now == 1) {rebalance(manager, address_of(manager), pool_name);};

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        event::emit_event<MiraPoolUpdateEvent>(
            &mut miraStatus.update_pool_events,
            MiraPoolUpdateEvent {
                pool_name: pool_name_str,
                pool_owner: manager_addr,
                pool_address: address_of(&pool_signer),
                privacy_allocation: 0,
                timestamp: 0// timestamp::now_seconds()
            }
        )
    }

    entry fun get_pool_signer(manager: address, pool_name: vector<u8>): signer acquires MiraAccount {
        let owner = borrow_global_mut<MiraAccount>(manager);

        let pool_signer_capability = table_with_length::borrow_mut<String, SignerCapability>(
            &mut owner.created_pools,
            string::utf8(pool_name)
        );
        let pool_signer = account::create_signer_with_capability(pool_signer_capability);
        return pool_signer
    }

    public entry fun invest<CoinX>(
        investor: &signer,
        pool_name: vector<u8>,
        pool_owner: address,
        amount: u64
    )acquires MiraPool, MiraAccount, MiraStatus, MiraUserWithdraw, MiraFees
    {
        let investor_addr = address_of(investor);
        assert!(exists<MiraAccount>(investor_addr) && exists<MiraAccount>(pool_owner),
            CREATE_MIRA_ACCOUNT
        );
        assert!(amount > 0, INVALID_PARAMETER);

        let investment_fee = borrow_global_mut<MiraFees>(MODULE_ADMIN).creation;
        amount = amount * ((TOTAL_INVESTOR_STAKE - investment_fee)/ TOTAL_INVESTOR_STAKE);
        transfer<CoinX>(investor, MODULE_ADMIN, (amount * investment_fee) / TOTAL_INVESTOR_STAKE);

        let investor_acct = borrow_global_mut<MiraAccount>(investor_addr);
        investor_acct.total_funds_invested = investor_acct.total_funds_invested + amount;

        let pool_signer = get_pool_signer(pool_owner, pool_name);
        update_stakes(investor_addr, address_of(&pool_signer), amount, 0, get_fund_value<USDC>(pool_owner, pool_name));

        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        assert!(
            amount >= (mira_pool.minimum_contribution / UNIT_DECIMAL) * (get_exchange_rate<USDC, CoinX>(
            ) / UNIT_DECIMAL),
            INSUFFICIENT_FUNDS
        );

        mira_pool.investor_funds = mira_pool.investor_funds + amount;
        owner.funds_under_management = owner.funds_under_management + amount;

        coin::transfer<CoinX>(investor, address_of(&pool_signer), amount);

        if (mira_pool.rebalance_on_investment == 1) {
            rebalance(investor, pool_owner, pool_name);
        };

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        let now = 0; //timestamp::now_seconds();
        //emit deposit
        event::emit_event<MiraPoolDepositEvent>(
            &mut miraStatus.deposit_pool_events,
            MiraPoolDepositEvent {
                pool_name: string::utf8(pool_name),
                investor: investor_addr,
                amount, // make sure to update this w/o fee
                timestamp: now
            }
        );

        let pool_addr = address_of(&pool_signer);
        if (!exists<MiraUserWithdraw>(investor_addr)) {
            let last_withdraw_timestamp = simple_map::create<address, u64>();
            simple_map::add(&mut last_withdraw_timestamp, pool_addr, now);
            move_to(investor, MiraUserWithdraw {
                last_withdraw_timestamp
            });
        } else {
            let mira_user_withdraw_status = borrow_global_mut<MiraUserWithdraw>(investor_addr);
            if (simple_map::contains_key(&mira_user_withdraw_status.last_withdraw_timestamp, &pool_addr)) {
                let value = simple_map::borrow_mut(&mut mira_user_withdraw_status.last_withdraw_timestamp, &pool_addr);
                *value = now;
            }else {
                simple_map::add(&mut mira_user_withdraw_status.last_withdraw_timestamp, pool_addr, now);
            };
        };
    }

    entry fun update_stakes(investor: address, pool_addr: address, amount: u64,
                            invest_or_withdraw: u8, fund_value: u64)acquires MiraPool {
        let mira_pool = borrow_global_mut<MiraPool>(pool_addr);
        let stake_divisor = (fund_value + amount) / (amount / 10000);
        let fee = (mira_pool.management_fee / stake_divisor) * 10000;
        let stake_map = &mut mira_pool.investors;

        if (invest_or_withdraw == 1) { stake_divisor = (fund_value - amount) / (amount / 10000); };

        //change every previous investor's stake by %
        let i = 0;
        let key = head_key(stake_map);
        while (i < iterable_table::length(stake_map)) {
            let (_, _, next) = borrow_iter(stake_map, *option::borrow(&key));
            let val = iterable_table::borrow_mut(stake_map, *option::borrow(&key));

            // iterate through all previous investors
            if (invest_or_withdraw == 0) {
                *val = *val - (*val / stake_divisor * 10000);
                // current investor's stake
                if (option::borrow(&key) == &investor) {
                    *val = *val + (TOTAL_INVESTOR_STAKE / stake_divisor * 10000) - fee;
                };
                // manager's stake
                if (option::borrow(&key) == &mira_pool.manager_addr) {
                    *val = *val + fee;
                }
            } else {
                if (option::borrow(&key) == &investor) {
                    *val = *val - (amount * UNIT_DECIMAL * 100 / fund_value);
                };
                *val = *val + (*val / stake_divisor * 10000);
            };

            key = next;
            i = i + 1;
        };
        if (!iterable_table::contains(stake_map, investor)) {
            iterable_table::add(stake_map, investor, (TOTAL_INVESTOR_STAKE / stake_divisor * 10000) - fee);
        };
    }

    public entry fun yearly_management(manager: &signer, manager_addr: address, pool_name: vector<u8>)acquires MiraAccount, MiraPool, MiraFees {
        // TODO: make sure this can only be called once yearly, and test to see if works
        assert!(exists<MiraAccount>(address_of(manager)),
            CREATE_MIRA_ACCOUNT
        );

        assert!(address_of(manager) == MODULE_ADMIN || address_of(manager) == manager_addr, INVALID_PARAMETER);
        let admin = 0;
        if (address_of(manager) == MODULE_ADMIN){ admin = 1;};

        let pool_signer = get_pool_signer(manager_addr, pool_name);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        let stake_map = &mut mira_pool.investors;
        let fee = mira_pool.management_fee;
        if (admin == 1) {
            fee = borrow_global_mut<MiraFees>(MODULE_ADMIN).management;
        };

        assert!(fee > 0, INVALID_PARAMETER);

        let i = 0;
        let key = head_key(stake_map);
        while (i < iterable_table::length(stake_map)) {
            let (_, _, next) = borrow_iter(stake_map, *option::borrow(&key));
            let val = iterable_table::borrow_mut(stake_map, *option::borrow(&key));

            if (option::borrow(&key) == &address_of(manager)) {
                *val = *val + fee;
            } else {
                 *val = *val - (*val * fee / TOTAL_INVESTOR_STAKE);
            };
            key = next;
            i = i + 1;
        };
        // if (admin == 1){
        //     withdraw<APT>()
        // }// TODO: update mira_pool. ...
    }

    public entry fun withdraw<CoinX>(
        investor: &signer,
        pool_name: vector<u8>,
        pool_owner: address,
        amount: u64
    )acquires MiraPool, MiraAccount, MiraStatus, MiraUserWithdraw, LockWithdrawals
    {
        assert!(borrow_global_mut<LockWithdrawals>(MODULE_ADMIN).lock == 0, WITHDRAWALS_LOCKED_FOR_USER_SAFETY);
        assert!(exists<MiraAccount>(address_of(investor)) && exists<MiraAccount>(pool_owner),
            CREATE_MIRA_ACCOUNT
        );

        // so that investor can withdraw with any token
        register_coin<CoinX>(investor);

        let investor_addr = address_of(investor);
        let fund_value = get_fund_value<USDC>(pool_owner, pool_name);
        let pool_signer = get_pool_signer(pool_owner, pool_name);
        let mira_pool_temp = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        // if amount > amount available to withdraw, withdraw max amount
        let investor_stake = borrow(&mira_pool_temp.investors, address_of(investor));
        if (amount > (fund_value * *investor_stake) / TOTAL_INVESTOR_STAKE) {
            amount = (fund_value * *investor_stake) / TOTAL_INVESTOR_STAKE;
            assert!(*investor_stake >= (amount * fund_value) / TOTAL_INVESTOR_STAKE, fund_value);
        };
        assert!(amount > 0, INVALID_PARAMETER);

        update_stakes(investor_addr, address_of(&pool_signer), amount, 1, fund_value);

        let owner = borrow_global_mut<MiraAccount>(pool_owner);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        let user_withdraw_status = borrow_global_mut<MiraUserWithdraw>(investor_addr);
        let now = 0; // timestamp::now_seconds();
        let last_timestamp = simple_map::borrow_mut<address, u64>(
            &mut user_withdraw_status.last_withdraw_timestamp,
            &address_of(&pool_signer)
        );

        if (mira_pool.minimum_withdrawal_period > 0) {
            assert!(
                *last_timestamp + mira_pool.minimum_withdrawal_period * SEC_OF_DAY < now,
                WITHDRAWAL_PERIOD_NOT_REACHED
            );
        } else { *last_timestamp = now; };

        let i = 0;
        let initial_balance = coin::balance<CoinX>(address_of(&pool_signer));
        while (i < vector::length(&mira_pool.token_names)) {
            let name = string::utf8(*vector::borrow<vector<u8>>(&mira_pool.token_names, i));

            if (name == symbol<USDC>()) {withdraw_helper<USDC, APT>(&pool_signer, amount, fund_value, initial_balance);};
            if (name == symbol<BTC>()) {withdraw_helper<BTC, APT>(&pool_signer, amount, fund_value, initial_balance);};
            if (name == symbol<ETH>()) {withdraw_helper<ETH, APT>(&pool_signer, amount, fund_value, initial_balance);};
            if (name == symbol<SOL>()) {withdraw_helper<SOL, APT>(&pool_signer, amount, fund_value, initial_balance);};
            i = i + 1;
        };


        coin::transfer<CoinX>(&pool_signer, investor_addr, amount);
        mira_pool.investor_funds = mira_pool.investor_funds - amount;

        owner.funds_under_management = owner.funds_under_management - amount;

        let investor_acct = borrow_global_mut<MiraAccount>(investor_addr);
        investor_acct.total_funds_invested = investor_acct.total_funds_invested - amount;

        let miraStatus = borrow_global_mut<MiraStatus>(MODULE_ADMIN);
        //emit deposit
        event::emit_event<MiraPoolWithdrawEvent>(
            &mut miraStatus.withdraw_pool_events,
            MiraPoolWithdrawEvent {
                pool_name: string::utf8(pool_name),
                investor: investor_addr,
                amount,
                timestamp: 0 //timestamp::now_seconds()
            }
        );
    }

    entry fun withdraw_helper<CoinX, CoinY>(pool_signer: &signer, amount: u64, fund_value: u64, initial_balance: u64){
        let swap_amount = (amount / (fund_value - initial_balance / UNIT_DECIMAL)) * coin::balance<USDC>(address_of(pool_signer));
        swap<CoinX, CoinY>(
            pool_signer,
            swap_amount
        );
    }

    entry fun rebalance_helper<CoinX, CoinY>(pool_signer: &signer, amount: u64, buy_or_sell: u8){
        if (buy_or_sell == 0){
            if (coin::balance<CoinX>(address_of(pool_signer)) < amount) {
                swap<CoinY, CoinX>(pool_signer, amount - coin::balance<ETH>(address_of(pool_signer)));
            }
        } else {
            if (coin::balance<CoinX>(address_of(pool_signer)) > amount) {
                swap<CoinX, CoinY>(pool_signer, coin::balance<ETH>(address_of(pool_signer)) - amount);
            }
        };
    }

    public entry fun rebalance(signer: &signer, manager: address, pool_name: vector<u8>)acquires MiraAccount, MiraPool {
        assert!(exists<MiraAccount>(address_of(signer)) && exists<MiraAccount>(manager), CREATE_MIRA_ACCOUNT);

        let pool_signer = get_pool_signer(manager, pool_name);
        let pool_addr = address_of(&pool_signer);
        let mira_pool = borrow_global_mut<MiraPool>(pool_addr);

        assert!(address_of(signer) == manager || mira_pool.rebalance_on_investment == 1, NO_REBALANCE_PERMISSION);

        let i = 0;
        let j = 0;

        // first loop: sell all tokens in excess
        while (i < vector::length(&mira_pool.token_names)) {
            let name = string::utf8(*vector::borrow<vector<u8>>(&mira_pool.token_names, i));
            let index_allocation = vector::borrow<u64>(&mira_pool.token_allocations, i);
            let target_amount = mira_pool.investor_funds * (*index_allocation as u64) / 100;

            // TODO: decide whether to use local 'APT' token for testing
            // and more importantly, should we create a local MiraAccount that stores funds?
            // think about wallet interaction, transferrability, and cost for connecting wallet, and
            // how we'd incorporate other chains
            // preregister tokens on wallet?
            // in the future, maybe connect our own wallet so that users never have to withdraw back to the wallet(s)
            // they connected

            if (name == symbol<USDC>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 1); };
            if (name == symbol<BTC>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 1); };
            if (name == symbol<ETH>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 1); };
            if (name == symbol<SOL>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 1); };

            i = i + 1;
        };

        // second loop: buy all tokens in shortage
        while (j < vector::length(&mira_pool.token_names)) {
            let name = string::utf8(*vector::borrow<vector<u8>>(&mira_pool.token_names, j));
            let index_allocation = vector::borrow<u64>(&mira_pool.token_allocations, j);
            let target_amount = mira_pool.investor_funds * (*index_allocation as u64) / 100;

            if (name == symbol<USDC>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 0); };
            if (name == symbol<BTC>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 0); };
            if (name == symbol<ETH>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 0); };
            if (name == symbol<SOL>()) {rebalance_helper<USDC, APT>(&pool_signer, target_amount, 0); };

            j = j + 1;
        };
    }

    entry fun swap<coinX, coinY>(signer: &signer, amount: u64) {
        //assert!(vector::contains(&VALID_TOKENS, coinX, INVALID_PARAMETER);
        let _pool_addr = address_of(signer);
        register_coin<coinY>(signer);
        let _ = amount;


        // burn<coinX>(signer, amount);
        // mint<coinY>(signer, address_of(signer), amount * (get_exchange_rate<coinY>() / get_exchange_rate<coinX>()));

        // for now, passing in string names, but should find a way to make generic function below work for liquidswap
        //     let sell = coin::withdraw<coinX>(&pool_signer, amount);
        //     let buy = router::get_amount_out<coinX, coinY, Uncorrelated>(amount);
        //
        //     let swap = router::swap_exact_coin_for_coin<coinX, coinY, Uncorrelated>(
        //         sell,
        //         buy
        //     );
        //     if (!coin::is_account_registered<coinY>(pool_addr)){
        //         coin::register<coinY>(&pool_signer)
        //     };
        //     coin::deposit(pool_addr, buy);

        // if (coin1 == string::utf8(b"APT") && coin2 == string::utf8(b"BTC")) {
        //     let sell = coin::withdraw<AptosCoin>(signer, amount);
        //     let buy = router_v2::swap_exact_coin_for_coin<AptosCoin, BTC, Uncorrelated>(
        //         sell,
        //         amount // need to * exchange rate * 0.99
        //     );
        //
        //     if (!coin::is_account_registered<BTC>(address_of(signer))) {
        //         coin::register<BTC>(signer);
        //     };
        //
        //     coin::deposit(address_of(signer), buy);
        // };
        //
        // if (coin1 == string::utf8(b"BTC") && coin2 == string::utf8(b"APT")) {
        //     let sell = coin::withdraw<BTC>(signer, amount);
        //     let buy = router_v2::swap_exact_coin_for_coin<BTC, AptosCoin, Uncorrelated>(
        //         sell,
        //         amount // need to * exchange rate * 0.99
        //     );
        //     coin::deposit(address_of(signer), buy);
        // };
        //
        // if (coin1 == string::utf8(b"APT") && coin2 == string::utf8(b"ETH")) {
        //     let sell = coin::withdraw<AptosCoin>(signer, amount);
        //     let buy = router_v2::swap_exact_coin_for_coin<AptosCoin, ETH, Uncorrelated>(
        //         sell,
        //         amount // need to * exchange rate * 0.99
        //     );
        //
        //     if (!coin::is_account_registered<ETH>(address_of(signer))) {
        //         coin::register<ETH>(signer);
        //     };
        //
        //     coin::deposit(address_of(signer), buy);
        // };
        //
        // if (coin1 == string::utf8(b"ETH") && coin2 == string::utf8(b"APT")) {
        //     let sell = coin::withdraw<ETH>(signer, amount);
        //     let buy = router_v2::swap_exact_coin_for_coin<ETH, AptosCoin, Uncorrelated>(
        //         sell,
        //         amount // need to * exchange rate * 0.99
        //     );
        //     coin::deposit(address_of(signer), buy);
        // };
        //
        // if (coin1 == string::utf8(b"APT") && coin2 == string::utf8(b"SOL")) {
        //     let sell = coin::withdraw<AptosCoin>(signer, amount);
        //     let buy = router_v2::swap_exact_coin_for_coin<AptosCoin, SOL, Uncorrelated>(
        //         sell,
        //         amount // need to * exchange rate * 0.99
        //     );
        //
        //     if (!coin::is_account_registered<SOL>(address_of(signer))) {
        //         coin::register<SOL>(signer);
        //     };
        //
        //     coin::deposit(address_of(signer), buy);
        // };
        //
        // if (coin1 == string::utf8(b"SOL") && coin2 == string::utf8(b"APT")) {
        //     let sell = coin::withdraw<SOL>(signer, amount);
        //     let buy = router_v2::swap_exact_coin_for_coin<SOL, AptosCoin, Uncorrelated>(
        //         sell,
        //         amount // need to * exchange rate * 0.99
        //     );
        //     coin::deposit(address_of(signer), buy);
        // };
    }

    entry fun get_fund_value<CoinX>(manager: address, pool_name: vector<u8>): u64 acquires MiraAccount, MiraPool {
        let pool_signer = address_of(&get_pool_signer(manager, pool_name));
        let gas_value = borrow_global<MiraPool>(pool_signer).gas_funds;

        let value = 0;
        value = value + coin::balance<APT>(pool_signer) * get_exchange_rate<CoinX, APT>() / UNIT_DECIMAL;
        value = value + coin::balance<USDC>(pool_signer) * get_exchange_rate<CoinX, USDC>() / UNIT_DECIMAL;
        value = value + coin::balance<BTC>(pool_signer) * get_exchange_rate<CoinX, BTC>() / UNIT_DECIMAL;
        value = value + coin::balance<ETH>(pool_signer) * get_exchange_rate<CoinX, ETH>() / UNIT_DECIMAL;
        value = value + coin::balance<SOL>(pool_signer) * get_exchange_rate<CoinX, SOL>() / UNIT_DECIMAL;

        return value - gas_value
    }

    entry fun get_exchange_rate<coinX, coinY>(): u64 {
        // use Pyth / Switchboard / other oracle
        //assert!(vector::contains(&VALID_TOKENS, &coin), INVALID_PARAMETER);
        let dividend = 1;
        let divisor = 1;
        if (symbol<coinX>() == string::utf8(b"APT")) { dividend = 10 };
        if (symbol<coinY>() == string::utf8(b"APT")) { divisor = 10 };
        if (symbol<coinX>() == string::utf8(b"USDC")) { dividend = 1 };
        if (symbol<coinX>() == string::utf8(b"USDC")) { divisor = 1 };
        if (symbol<coinX>() == string::utf8(b"BTC")) { dividend = 15000 };
        if (symbol<coinX>() == string::utf8(b"BTC")) { divisor = 15000 };
        if (symbol<coinX>() == string::utf8(b"ETH")) { dividend = 1000 };
        if (symbol<coinX>() == string::utf8(b"ETH")) { divisor = 1000 };
        if (symbol<coinX>() == string::utf8(b"SOL")) { dividend = 20 };
        if (symbol<coinX>() == string::utf8(b"SOL")) { divisor = 20 };
        return dividend * UNIT_DECIMAL / divisor
    }

    entry fun check_tokens(token_names: vector<vector<u8>>, token_allocations: vector<u64>) {
        let sum_allocation: u64 = 0;
        let i = 0;
        let token_check = vector::empty<vector<u8>>();
        while (i < vector::length(&token_names)) {
            let name = vector::borrow(&token_names, i);
            let alloc: u64 = *vector::borrow(&token_allocations, i);

            assert!(vector::contains(&VALID_TOKENS, name) && !vector::contains(&token_check, name), INVALID_PARAMETER);
            assert!(alloc < 100, INVALID_PARAMETER);

            vector::push_back(&mut token_check, *name);
            sum_allocation = sum_allocation + alloc;
            i = i + 1;
        };
        assert!(sum_allocation == 100, INVALID_PARAMETER);
    }

    // add or remove gas funds
    public entry fun change_gas_funds(
        manager: &signer,
        pool_name: vector<u8>,
        amount: u64,
        add_or_remove: u8
    )acquires MiraAccount, MiraPool {
        let pool_signer = get_pool_signer(address_of(manager), pool_name);
        let owner = borrow_global_mut<MiraAccount>(address_of(manager));
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));

        if (add_or_remove == 1) {
            // withdrawing
            assert!(amount <= mira_pool.gas_funds, INSUFFICIENT_FUNDS);
            coin::transfer<APT>(&pool_signer, address_of(manager), amount);
            owner.funds_on_gas = owner.funds_on_gas - amount;
            mira_pool.gas_funds = mira_pool.gas_funds - amount;
        } else {
            // adding
            coin::transfer<APT>(manager, address_of(&pool_signer), amount);
            owner.funds_on_gas = owner.funds_on_gas + amount;
            mira_pool.gas_funds = mira_pool.gas_funds + amount;
        }
    }

    public entry fun transfer_manager(_current_owner: &signer,
                                      _new_owner: address, _pool_name: vector<u8>) {}

    //Move Pool from owner to Admin
    public entry fun repossess(
        admin: &signer,
        user: address, pool_name: vector<u8>
    )acquires MiraPool, MiraAccount
    {
        let admin_addr = address_of(admin);
        assert!(admin_addr == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);

        let pool_signer = get_pool_signer(user, pool_name);
        let owner = borrow_global_mut<MiraAccount>(user);

        // repossessing the pool this way gives Mira has direct ownership of the pool
        // would be better to keep pool under resource account, and move pool signer capability from
        // manager's created_pools to mira's created_pools
        let pool = move_from<MiraPool>(address_of(&pool_signer));
        move_to<MiraPool>(admin, pool);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(admin));

        // update pool settings
        mira_pool.management_fee = 10;
        mira_pool.manager_addr = admin_addr;

        // change lists
        table_with_length::remove(&mut owner.created_pools, string::utf8(pool_name));

        // update previous owner info
        owner.funds_under_management = owner.funds_under_management - mira_pool.investor_funds;
        owner.funds_on_gas = owner.funds_on_gas - mira_pool.gas_funds;

        // update mira info
        let mira = borrow_global_mut<MiraAccount>(admin_addr);
        mira.funds_under_management = mira.funds_under_management + mira_pool.investor_funds;
        mira.funds_on_gas = mira.funds_on_gas + mira_pool.gas_funds;
    }

    public entry fun lock_withdrawals(admin: &signer)acquires LockWithdrawals {
        assert!(address_of(admin) == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);
        let change_value = borrow_global_mut<LockWithdrawals>(address_of(admin));
        change_value.lock = 1;
    }

    public entry fun unlock_withdrawals(admin: &signer)acquires LockWithdrawals {
        assert!(address_of(admin) == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);
        let change_value = borrow_global_mut<LockWithdrawals>(address_of(admin));
        change_value.lock = 0;
    }

    public entry fun update_creation_fee(admin: &signer, fee: u64)acquires MiraFees {
        assert!(address_of(admin) == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);
        assert!(fee < MAX_MANAGEMENT_FEE, INVALID_PARAMETER);
        let change_value = borrow_global_mut<MiraFees>(address_of(admin));
        change_value.creation = fee;
    }

    public entry fun update_investment_fee(admin: &signer, fee: u64)acquires MiraFees {
        assert!(address_of(admin) == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);
        assert!(fee < MAX_MANAGEMENT_FEE, INVALID_PARAMETER);
        let change_value = borrow_global_mut<MiraFees>(address_of(admin));
        change_value.investment = fee;
    }

    public entry fun update_management_fee(admin: &signer, fee: u64)acquires MiraFees {
        assert!(address_of(admin) == MODULE_ADMIN, INVALID_ADMIN_ADDRESS);
        assert!(fee < MAX_MANAGEMENT_FEE, INVALID_PARAMETER);
        let change_value = borrow_global_mut<MiraFees>(address_of(admin));
        change_value.management = fee;
    }

    entry fun register_coin<coinX>(signer: &signer) {
        if (!coin::is_account_registered<coinX>(address_of(signer))) {
            coin::register<coinX>(signer);
        }
    }

    #[test_only]
    public fun print_pool_info(user: &signer, pool_name: vector<u8>) acquires MiraAccount, MiraPool {
        let pool_signer = get_pool_signer(address_of(user), pool_name);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        debug::print(&string::utf8(b"name:"));
        debug::print(&mira_pool.pool_name);
        debug::print(&string::utf8(b"token names:"));
        debug::print(&mira_pool.token_names);
        debug::print(&string::utf8(b"token allocations:"));
        debug::print(&mira_pool.token_allocations);
        debug::print(&string::utf8(b"management fee:"));
        debug::print(&mira_pool.management_fee);
        debug::print(&string::utf8(b"investor funds:"));
        debug::print(&mira_pool.investor_funds);
        debug::print(&string::utf8(b"gas funds:"));
        debug::print(&mira_pool.gas_funds);
        debug::print(&string::utf8(b"rebalance on investment:"));
        debug::print(&mira_pool.rebalance_on_investment);
        debug::print(&string::utf8(b"rebalancing period:"));
        debug::print(&mira_pool.rebalancing_period);
        debug::print(&string::utf8(b"time created:"));
        debug::print(&mira_pool.time_created);
    }

    #[test_only]
    public fun print_investor_stakes(manager: address, pool_name: vector<u8>) acquires MiraAccount, MiraPool {
        let pool_signer = get_pool_signer(manager, pool_name);
        let mira_pool = borrow_global_mut<MiraPool>(address_of(&pool_signer));
        let stake_map = &mut mira_pool.investors;

        let key = head_key(stake_map);
        let i = 0;

        debug::print(&string::utf8(b"investor stakes: "));

        while (i < iterable_table::length(stake_map)) {
            let (_, _, next) = borrow_iter(stake_map, *option::borrow(&key));
            let val = iterable_table::borrow_mut(stake_map, *option::borrow(&key));
            debug::print(&key);
            debug::print(val);
            key = next;
            i = i + 1
        }
    }

    #[test_only]
    public fun print_account_info(user: &signer) acquires MiraAccount {
        let acct = borrow_global_mut<MiraAccount>(address_of(user));
        debug::print(acct);
        debug::print(&string::utf8(b"APT:"));
        debug::print(&balance<APT>(address_of(user)));
        debug::print(&string::utf8(b"USDC:"));
        debug::print(&balance<USDC>(address_of(user)));
        debug::print(&string::utf8(b"BTC:"));
        debug::print(&balance<BTC>(address_of(user)));
        debug::print(&string::utf8(b"ETH:"));
        debug::print(&balance<ETH>(address_of(user)));
        debug::print(&string::utf8(b"SOL:"));
        debug::print(&balance<SOL>(address_of(user)));
    }

    #[test_only]
    public fun print_real_pool_distribution(manager: address, pool_name: String)acquires MiraAccount {
        let pool_signer = get_pool_signer(manager, *string::bytes(&pool_name));

        debug::print(&string::utf8(b"APT:"));
        debug::print(&balance<APT>(address_of(&pool_signer)));
        debug::print(&string::utf8(b"USDC:"));
        debug::print(&balance<USDC>(address_of(&pool_signer)));
        debug::print(&string::utf8(b"BTC:"));
        debug::print(&balance<BTC>(address_of(&pool_signer)));
        debug::print(&string::utf8(b"ETH:"));
        debug::print(&balance<ETH>(address_of(&pool_signer)));
        debug::print(&string::utf8(b"SOL:"));
        debug::print(&balance<SOL>(address_of(&pool_signer)));
    }
}
