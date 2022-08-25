
<a name="0x1_LiquidityPool"></a>

# Module `0x1::LiquidityPool`



-  [Resource `LiquidityPoolInfo`](#0x1_LiquidityPool_LiquidityPoolInfo)
-  [Constants](#@Constants_0)
-  [Function `add_to_pool`](#0x1_LiquidityPool_add_to_pool)
-  [Function `init_lp`](#0x1_LiquidityPool_init_lp)


<pre><code><b>use</b> <a href="">0x1::account</a>;
<b>use</b> <a href="">0x1::resource_account</a>;
</code></pre>



<a name="0x1_LiquidityPool_LiquidityPoolInfo"></a>

## Resource `LiquidityPoolInfo`



<pre><code><b>struct</b> <a href="LiquidityPool.md#0x1_LiquidityPool_LiquidityPoolInfo">LiquidityPoolInfo</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>signer_cap: <a href="_SignerCapability">account::SignerCapability</a></code>
</dt>
<dd>

</dd>
<dt>
<code>amount: u8</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="@Constants_0"></a>

## Constants


<a name="0x1_LiquidityPool_ADMIN"></a>



<pre><code><b>const</b> <a href="LiquidityPool.md#0x1_LiquidityPool_ADMIN">ADMIN</a>: <b>address</b> = 59b0135f93fc9c89613523d47a92e652a57a42193f463ae9d4bd17188ed7cc93;
</code></pre>



<a name="0x1_LiquidityPool_add_to_pool"></a>

## Function `add_to_pool`



<pre><code><b>public</b> <b>fun</b> <a href="LiquidityPool.md#0x1_LiquidityPool_add_to_pool">add_to_pool</a>(lp: <a href="LiquidityPool.md#0x1_LiquidityPool_LiquidityPoolInfo">LiquidityPool::LiquidityPoolInfo</a>, funds: u8): <a href="LiquidityPool.md#0x1_LiquidityPool_LiquidityPoolInfo">LiquidityPool::LiquidityPoolInfo</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="LiquidityPool.md#0x1_LiquidityPool_add_to_pool">add_to_pool</a>(lp: <a href="LiquidityPool.md#0x1_LiquidityPool_LiquidityPoolInfo">LiquidityPoolInfo</a>, funds: u8): <a href="LiquidityPool.md#0x1_LiquidityPool_LiquidityPoolInfo">LiquidityPoolInfo</a> {
    lp.amount = lp.amount + funds;
    <b>return</b> lp
}
</code></pre>



</details>

<a name="0x1_LiquidityPool_init_lp"></a>

## Function `init_lp`



<pre><code><b>public</b> <b>fun</b> <a href="LiquidityPool.md#0x1_LiquidityPool_init_lp">init_lp</a>(source: &<a href="">signer</a>): <a href="">signer</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="LiquidityPool.md#0x1_LiquidityPool_init_lp">init_lp</a>(source: &<a href="">signer</a>): <a href="">signer</a> {
    <b>let</b> signer_cap = retrieve_resource_account_cap(source, <a href="LiquidityPool.md#0x1_LiquidityPool_ADMIN">ADMIN</a>);
    <b>let</b> lp_signer = create_signer_with_capability(&signer_cap);
    <b>let</b> lp = <a href="LiquidityPool.md#0x1_LiquidityPool_LiquidityPoolInfo">LiquidityPoolInfo</a> {
        signer_cap,
        amount: 0
    };
    <b>move_to</b>(&lp_signer, lp);
    <b>return</b> lp_signer
}
</code></pre>



</details>
