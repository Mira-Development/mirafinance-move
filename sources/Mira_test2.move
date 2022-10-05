#[test_only]
module mira::mira_test2 {
    //use std::string;
    use aptos_framework::account;
    //use aptos_framework::timestamp;
    use aptos_framework::managed_coin;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin::{Self, MintCapability, BurnCapability, transfer};
    use mira::mira;
    use aptos_framework::timestamp;
    use std::string::String;
    use std::string;
    use std::signer::address_of;
    use mira::mira::{print_pool_info};
    use aptos_std::table_with_length;

    struct AptosCoinTest has key {
        mint_cap: MintCapability<AptosCoin>,
        burn_cap: BurnCapability<AptosCoin>
    }

    #[test(creator = @mira, user = @0123, aptos_framework = @aptos_framework)]
    public entry fun test_init_mira(
        creator: &signer,
        user: &signer,
        aptos_framework: &signer
    ) acquires AptosCoinTest {
        let creator_addr = address_of(creator);
        account::create_account_for_test(creator_addr);
        mira::init_mira(creator);

        //mint 10000 coin for creator
        let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
        let coins_minted = coin::mint<AptosCoin>(10000, &mint_cap);

        if (!coin::is_account_registered<AptosCoin>(creator_addr)) {
            managed_coin::register<AptosCoin>(creator);
        };

        coin::deposit<AptosCoin>(creator_addr, coins_minted);

        move_to(creator, AptosCoinTest {
            mint_cap,
            burn_cap
        });
        mira::connect_account(user, b"randomizestr");

        let user_addr = address_of(user);
        account::create_account_for_test(user_addr);

        //mint 10000 aptos  to user
        let aptosCoinTest = borrow_global<AptosCoinTest>(address_of(creator));
        let coins_minted = coin::mint<AptosCoin>(10000, &aptosCoinTest.mint_cap);
        if (!coin::is_account_registered<AptosCoin>(user_addr)) {
            managed_coin::register<AptosCoin>(user);
        };
        coin::deposit<AptosCoin>(user_addr, coins_minted);

        timestamp::set_time_has_started_for_testing(aptos_framework);

        let tokens = table_with_length::new<u64, String>();
        table_with_length::add(&mut tokens, 0, string::utf8(b"BTC"));
        table_with_length::add(&mut tokens, 1, string::utf8(b"ETH"));

        let token_allocations = table_with_length::new<u64, u64>();
        table_with_length::add(&mut token_allocations, 0, 50);
        table_with_length::add(&mut token_allocations, 1, 50);

        let poolsettings = mira::create_pool_settings(
            0,
            0,
            5,
            0,
            0,
            0,
            0
        );


        mira::create_pool(
            user,
            b"pool_name",
            tokens,
            token_allocations,
            1000,
            poolsettings,
        );
        print_pool_info(user, string::utf8(b"pool_name"));
        mira::invest(user, b"pool_name", address_of(user), 100);
        mira::invest(creator, b"pool_name", address_of(user), 200);
        print_pool_info(user, string::utf8(b"pool_name"));
        mira::withdraw(user, b"pool_name", address_of(user), 1100);
        //mira::withdraw(creator, b"pool_name", address_of(user), 300);
        print_pool_info(user, string::utf8(b"pool_name"));
        transfer<AptosCoin>(user, address_of(creator), 10000);
        transfer<AptosCoin>(creator, address_of(user), 19800);


//        let input = none<TableWithLength<u64, String>>();
//        let input2 = none<TableWithLength<u64, u64>>();
//        let input3 = &true;
//        let input4 = none<MiraPoolSettings>();
//
//        update_pool(user, b"pool_name", input, &input2, input3, input4);
    }
}