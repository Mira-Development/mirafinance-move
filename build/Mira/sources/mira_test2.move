#[test_only]
module mira::mira_test2{
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
    use std::vector;
    use std::signer::address_of;
    use mira::mira::{print_pool_info};

    struct AptosCoinTest has key{
      mint_cap: MintCapability<AptosCoin>,
      burn_cap: BurnCapability<AptosCoin>
   }

   #[test(creator = @mira, user=@0123, aptos_framework = @aptos_framework)]
   public entry fun test_init_mira(
       creator: &signer,
       user: &signer,
       aptos_framework: &signer
   ) acquires AptosCoinTest {
       let creator_addr = address_of(creator);
       account::create_account_for_test(creator_addr);
       mira::init_mira(creator);

       //mint 10000 coin for creator
       let ( burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
       let coins_minted = coin::mint<AptosCoin>(10000, &mint_cap);

       if (!coin::is_account_registered<AptosCoin>(creator_addr)){
	     managed_coin::register<AptosCoin>(creator);
       };

       coin::deposit<AptosCoin>(creator_addr, coins_minted);

       move_to(creator, AptosCoinTest{
           mint_cap,
           burn_cap
       });
       mira::connect_account(user, b"randomizestr");

       let user_addr = address_of(user);
        account::create_account_for_test(user_addr);

        //mint 10000 aptos  to user
        let aptosCoinTest = borrow_global<AptosCoinTest>(address_of(creator));
        let coins_minted = coin::mint<AptosCoin>(10000, &aptosCoinTest.mint_cap);
        if (!coin::is_account_registered<AptosCoin>(user_addr)){
	      managed_coin::register<AptosCoin>(user);
        };
        coin::deposit<AptosCoin>(user_addr, coins_minted);

        timestamp::set_time_has_started_for_testing(aptos_framework);

        let coin_names = vector::empty<String>();
        vector::push_back(&mut coin_names, string::utf8(b"BTC"));
        vector::push_back(&mut coin_names, string::utf8(b"ETH"));

        let coin_amounts = vector::empty<u8>();
        vector::push_back(&mut coin_amounts, 50);
        vector::push_back(&mut coin_amounts, 50);

        mira::create_pool(
            user,
            b"pool_name",
            1000, //amount
            1000, //management_fee  10%
            0, //rebalancing_period
            1000, //minimum_contribution 10%
            0, //minium_withdrawal_period
            1000, //referral_reward 10%
            coin_names,
            coin_amounts,
            false
        );
       print_pool_info(user, string::utf8(b"pool_name"));
       mira::invest(user, b"pool_name", address_of(user), 100);
       mira::invest(creator, b"pool_name", address_of(user), 200);
       print_pool_info(user, string::utf8(b"pool_name"));
       mira::withdraw(user, b"pool_name", address_of(user), 1200);
       //mira::withdraw(creator, b"pool_name", address_of(user), 300);
       print_pool_info(user, string::utf8(b"pool_name"));
       transfer<AptosCoin>(user, address_of(creator), 10000);
       transfer<AptosCoin>(creator, address_of(user), 19800);
   }
}