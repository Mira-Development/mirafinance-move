module mira::oracle {
    use liquidswap::router_v2;
    use liquidswap::coin_helper;
    use overflowing_math::overflowing_u128::wrapping_sub;
    use aptos_std::debug::print;
    use std::string;

    const MAX_U64: u128 = 18446744073709551615;
    const PERIOD: u64 = 86400;

    struct Oracle<phantom X, phantom Y, phantom Curve> has key {
        x_cumulative_price: u128,
        y_cumulative_price: u128,
        x_price_average: u128,
        y_price_average: u128,
        last_timestamp: u64,
    }

    public fun init_oracle<X, Y, Curve>(account: &signer) {
        let (x_cumulative_price, y_cumulative_price, last_timestamp) = router_v2::get_cumulative_prices<X, Y, Curve>();

        move_to(account, Oracle<X, Y, Curve> {
            x_cumulative_price,
            y_cumulative_price,
            x_price_average: 0,
            y_price_average: 0,
            last_timestamp,
        });
    }

    public fun update<X, Y, Curve>(account_addr: address) acquires Oracle {
        let oracle = borrow_global_mut<Oracle<X, Y, Curve>>(account_addr);

        let (x_cumulative_price, y_cumulative_price, last_timestamp) = router_v2::get_cumulative_prices<X, Y, Curve>();
        let time_elapsed = last_timestamp - oracle.last_timestamp;
        assert!(time_elapsed >= PERIOD, time_elapsed);

        oracle.x_price_average = (wrapping_sub(x_cumulative_price, oracle.x_cumulative_price) / (time_elapsed as u128));
        oracle.y_price_average = (wrapping_sub(y_cumulative_price, oracle.y_cumulative_price) / (time_elapsed as u128));
        print(&string::utf8(b"oracle"));
        print(&(oracle.x_price_average ));

        oracle.x_cumulative_price = x_cumulative_price;
        oracle.y_cumulative_price = y_cumulative_price;
        oracle.last_timestamp = last_timestamp;
    }

    public fun consult<X, Y, Curve>(oracle_addr: address, amount_x: u64): u64 acquires Oracle {
        let oracle = borrow_global<Oracle<X, Y, Curve>>(oracle_addr);

        let r = if (coin_helper::is_sorted<X, Y>()) {
            print(&(oracle.x_price_average ));
            oracle.x_price_average * (amount_x as u128) / MAX_U64
        } else {
            print(&(oracle.y_price_average));
            oracle.y_price_average * (amount_x as u128) / MAX_U64
        };

        (r as u64)
    }
}