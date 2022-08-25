
<a name="0x1_SimpleMira"></a>

# Module `0x1::SimpleMira`



-  [Resource `Pools`](#0x1_SimpleMira_Pools)
-  [Resource `Accounts`](#0x1_SimpleMira_Accounts)
-  [Resource `MiraPool`](#0x1_SimpleMira_MiraPool)
-  [Struct `MiraPoolSettings`](#0x1_SimpleMira_MiraPoolSettings)
-  [Resource `MiraAccount`](#0x1_SimpleMira_MiraAccount)
-  [Constants](#@Constants_0)
-  [Function `choose_pool_settings`](#0x1_SimpleMira_choose_pool_settings)
-  [Function `create_pool`](#0x1_SimpleMira_create_pool)


<pre><code><b>use</b> <a href="LiquidityPool.md#0x1_LiquidityPool">0x1::LiquidityPool</a>;
<b>use</b> <a href="">0x1::signer</a>;
<b>use</b> <a href="">0x1::table</a>;
</code></pre>



<a name="0x1_SimpleMira_Pools"></a>

## Resource `Pools`



<pre><code><b>struct</b> <a href="SimpleMira.md#0x1_SimpleMira_Pools">Pools</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>items: <a href="_Table">table::Table</a>&lt;<b>address</b>, <a href="_Table">table::Table</a>&lt;u64, <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">SimpleMira::MiraPool</a>&gt;&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_SimpleMira_Accounts"></a>

## Resource `Accounts`



<pre><code><b>struct</b> <a href="SimpleMira.md#0x1_SimpleMira_Accounts">Accounts</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>items: <a href="_Table">table::Table</a>&lt;<b>address</b>, <a href="SimpleMira.md#0x1_SimpleMira_MiraAccount">SimpleMira::MiraAccount</a>&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_SimpleMira_MiraPool"></a>

## Resource `MiraPool`



<pre><code><b>struct</b> <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">MiraPool</a> <b>has</b> store, key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_name: <a href="">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>manager: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>investors: <a href="_Table">table::Table</a>&lt;<b>address</b>, u64&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>index_allocation: <a href="_Table">table::Table</a>&lt;<a href="">vector</a>&lt;u8&gt;, u64&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>total_amount: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>settings: <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">SimpleMira::MiraPoolSettings</a></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_SimpleMira_MiraPoolSettings"></a>

## Struct `MiraPoolSettings`



<pre><code><b>struct</b> <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">MiraPoolSettings</a> <b>has</b> <b>copy</b>, drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>management_fee: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>rebalancing_period: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>minimum_contribution: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>minimum_withdrawal: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>referral_reward: u8</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_SimpleMira_MiraAccount"></a>

## Resource `MiraAccount`



<pre><code><b>struct</b> <a href="SimpleMira.md#0x1_SimpleMira_MiraAccount">MiraAccount</a> <b>has</b> store, key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>owner: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>account_name: <a href="">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>total_funds_invested: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>funds_under_management: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>funds_on_gas: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>funds_on_management: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>created_pools: <a href="_Table">table::Table</a>&lt;u64, <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">SimpleMira::MiraPool</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>invested_pools: <a href="_Table">table::Table</a>&lt;u64, <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">SimpleMira::MiraPool</a>&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="@Constants_0"></a>

## Constants


<a name="0x1_SimpleMira_ADMIN"></a>



<pre><code><b>const</b> <a href="SimpleMira.md#0x1_SimpleMira_ADMIN">ADMIN</a>: <b>address</b> = 59b0135f93fc9c89613523d47a92e652a57a42193f463ae9d4bd17188ed7cc93;
</code></pre>



<a name="0x1_SimpleMira_choose_pool_settings"></a>

## Function `choose_pool_settings`



<pre><code><b>public</b> <b>fun</b> <a href="SimpleMira.md#0x1_SimpleMira_choose_pool_settings">choose_pool_settings</a>(management_fee: u8, rebalancing_period: u8, minimum_contribution: u8, minimum_withdrawal: u8, referral_reward: u8): <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">SimpleMira::MiraPoolSettings</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="SimpleMira.md#0x1_SimpleMira_choose_pool_settings">choose_pool_settings</a>(
    management_fee: u8,
    rebalancing_period: u8,
    minimum_contribution: u8,
    minimum_withdrawal: u8,
    referral_reward:u8): <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">MiraPoolSettings</a> {

    <b>let</b> newsettings = <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">MiraPoolSettings</a>{
        management_fee,
        rebalancing_period,
        minimum_contribution,
        minimum_withdrawal,
        referral_reward
    };

    <b>return</b> newsettings
}
</code></pre>



</details>

<a name="0x1_SimpleMira_create_pool"></a>

## Function `create_pool`



<pre><code><b>public</b> <b>fun</b> <a href="SimpleMira.md#0x1_SimpleMira_create_pool">create_pool</a>(manager: &<a href="">signer</a>, pool_name: <a href="">vector</a>&lt;u8&gt;, index_allocation: <a href="_Table">table::Table</a>&lt;<a href="">vector</a>&lt;u8&gt;, u64&gt;, total_amount: u8, settings: <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">SimpleMira::MiraPoolSettings</a>): <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">SimpleMira::MiraPool</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="SimpleMira.md#0x1_SimpleMira_create_pool">create_pool</a>(
    manager: &<a href="">signer</a>,
    pool_name: <a href="">vector</a>&lt;u8&gt;,
    index_allocation: Table&lt;<a href="">vector</a>&lt;u8&gt;, u64&gt;,
    total_amount: u8,
    settings: <a href="SimpleMira.md#0x1_SimpleMira_MiraPoolSettings">MiraPoolSettings</a>): <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">MiraPool</a> {

    <b>let</b> pool_address = address_of(&init_lp(manager));

    <b>let</b> investors = <a href="_new">table::new</a>&lt;<b>address</b>, u64&gt;();

    <b>let</b> newpool = <a href="SimpleMira.md#0x1_SimpleMira_MiraPool">MiraPool</a> {
        pool_name,
        pool_address,
        manager: address_of(manager),
        investors,
        index_allocation,
        total_amount,
        settings
    };

    <b>return</b> newpool
}
</code></pre>



</details>
