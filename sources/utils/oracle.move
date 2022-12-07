module mira::oracle {
    use liquidswap::router_v2;
    use aptos_std::debug::print;
    use liquidswap::router_v2::get_reserves_size;
    use std::string;

    const MAX_U64: u128 = 18446744073709551615;
    const PERIOD: u64 = 86400;
    const UNIT_DECIMAL: u128 = 100000000;

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

        let (_res_x, _res_y) = get_reserves_size<X, Y, Curve>();

        let (x_cumulative_price, y_cumulative_price, last_timestamp) = router_v2::get_cumulative_prices<X, Y, Curve>();
        let time_elapsed = last_timestamp - oracle.last_timestamp;
        assert!(time_elapsed >= PERIOD, time_elapsed);

        // for now, test timer does not work for router_v2 bc time is not live, which makes pool.last_block_timestamp always = now_seconds(),
        // and get_cumulative_prices returns (0, 0, ...). change back to code below when going live.
        // oracle.x_price_average = (wrapping_sub(x_cumulative_price, oracle.x_cumulative_price) / (time_elapsed as u128));
        // oracle.y_price_average = (wrapping_sub(y_cumulative_price, oracle.y_cumulative_price) / (time_elapsed as u128));

        oracle.x_cumulative_price = x_cumulative_price;
        oracle.y_cumulative_price = y_cumulative_price;
        oracle.x_price_average = x_cumulative_price;
        oracle.y_price_average = y_cumulative_price;

        oracle.last_timestamp = last_timestamp;
    }

    public fun consult<X, Y, Curve>(oracle_addr: address, amount_x: u64, reverse: u8): u64 acquires Oracle {
        // print(&b"coin x: ");
        // print(&symbol<X>());
        // print(&b"coin y: ");
        // print(&symbol<Y>());
        // print(&b"amount_in");
        // print(&amount_x);
        // print(&b"amount_out");

        let r = if (reverse == 0) {
            borrow_global<Oracle<X, Y, Curve>>(oracle_addr).x_price_average * (amount_x as u128) / UNIT_DECIMAL // / MAX_U64
        } else {
            borrow_global<Oracle<Y, X, Curve>>(oracle_addr).y_price_average * (amount_x as u128) / UNIT_DECIMAL // / MAX_U64
        };

        (r as u64)
    }

    public fun print_oracle<X, Y, Curve>(oracle_addr: address) acquires Oracle {
        let oracle = borrow_global<Oracle<X, Y, Curve>>(oracle_addr);
        print(&string::utf8(b"x cumulative price: "));
        print(&oracle.x_cumulative_price);
        print(&string::utf8(b"y cumulative price: "));
        print(&oracle.y_cumulative_price);
        print(&string::utf8(b"x price average: "));
        print(&oracle.x_price_average);
        print(&string::utf8(b"y price average: "));
        print(&oracle.y_price_average);
    }
}