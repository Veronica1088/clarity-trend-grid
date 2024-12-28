import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can submit new trend",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('trend_grid', 'submit-trend', [
                types.ascii("NEW YORK"),
                types.ascii("SUMMER"),
                types.ascii("Minimalist Streetwear"),
                types.ascii("Urban fashion with clean lines and monochrome palette")
            ], wallet1.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(0);
        
        let getTrend = chain.callReadOnlyFn(
            'trend_grid',
            'get-trend',
            [types.uint(0)],
            wallet1.address
        );
        
        getTrend.result.expectOk().expectSome();
    }
});

Clarinet.test({
    name: "Cannot submit trend with invalid season",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('trend_grid', 'submit-trend', [
                types.ascii("NEW YORK"),
                types.ascii("INVALID"),
                types.ascii("Minimalist Streetwear"),
                types.ascii("Urban fashion with clean lines and monochrome palette")
            ], wallet1.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(101);
    }
});

Clarinet.test({
    name: "Can vote on trend only once",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;
        const wallet2 = accounts.get('wallet_2')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('trend_grid', 'submit-trend', [
                types.ascii("NEW YORK"),
                types.ascii("SUMMER"),
                types.ascii("Minimalist Streetwear"),
                types.ascii("Urban fashion with clean lines and monochrome palette")
            ], wallet1.address)
        ]);
        
        let voteBlock = chain.mineBlock([
            Tx.contractCall('trend_grid', 'vote-on-trend', [
                types.uint(0)
            ], wallet2.address),
            // Second vote should fail
            Tx.contractCall('trend_grid', 'vote-on-trend', [
                types.uint(0)
            ], wallet2.address)
        ]);
        
        voteBlock.receipts[0].result.expectOk().expectBool(true);
        voteBlock.receipts[1].result.expectErr().expectUint(103);
    }
});