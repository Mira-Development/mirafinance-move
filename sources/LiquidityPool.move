module 0x1::LiquidityPool {
    use aptos_framework::resource_account::retrieve_resource_account_cap;
    use aptos_framework::account::{create_signer_with_capability, SignerCapability};
    use 0x1::SimpleMira::{MiraPool, MiraPoolSettings};

    const ADMIN: address = @mira;

    struct LiquidityPoolInfo has key {
        signer_cap: SignerCapability,
        amount: u8
    }

    public fun add_to_pool(lp: LiquidityPoolInfo, funds: u8): LiquidityPoolInfo {
        lp.amount = lp.amount + funds;
        return lp
    }

    public fun init_lp(source: &signer): signer {
        let signer_cap = retrieve_resource_account_cap(source, ADMIN);
        let lp_signer = create_signer_with_capability(&signer_cap);
        let lp = LiquidityPoolInfo {
            signer_cap,
            amount: 0
        };
        move_to(&lp_signer, lp);
        return lp_signer
    }
}
