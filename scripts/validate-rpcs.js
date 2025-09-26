/**
 * Script to validate all RPC endpoints for connectivity and performance
 * Tests response times and basic functionality across all chains
 */

const { EcoRoutesChains, EcoChains } = require('@eco-foundation/chains');

const ecoChains = new EcoChains({
  alchemyKey: process.env.ALCHEMY_API_KEY,
  infuraKey: process.env.INFURA_API_KEY,
  curtisKey: process.env.CURTIS_API_KEY,
  mantaKey: process.env.MANTA_API_KEY
});

async function validateRpcEndpoint(url, chainId) {
  const start = Date.now();

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_blockNumber',
        params: [],
        id: 1
      })
    });

    const responseTime = Date.now() - start;

    if (!response.ok) {
      return { status: 'error', error: `HTTP ${response.status}`, responseTime };
    }

    const data = await response.json();

    if (data.error) {
      return { status: 'error', error: data.error.message, responseTime };
    }

    if (!data.result) {
      return { status: 'error', error: 'No result in response', responseTime };
    }

    const blockNumber = parseInt(data.result, 16);

    return {
      status: 'success',
      blockNumber,
      responseTime,
      url: url.replace(/\/[a-f0-9]{32,}/gi, '/***') // Mask API keys
    };
  } catch (error) {
    const responseTime = Date.now() - start;
    return {
      status: 'error',
      error: error.message,
      responseTime
    };
  }
}

async function validateAllRpcs() {
  console.log('=== RPC ENDPOINT VALIDATION ===\n');

  const results = [];
  const chains = EcoRoutesChains.sort((a, b) => a.id - b.id);

  for (const chain of chains) {
    console.log(`Testing ${chain.name} (ID: ${chain.id})...`);

    const rpcUrls = ecoChains.getRpcUrlsForChain(chain.id);

    for (const url of rpcUrls) {
      const result = await validateRpcEndpoint(url, chain.id);
      results.push({
        chainId: chain.id,
        chainName: chain.name,
        ...result
      });

      const statusIcon = result.status === 'success' ? '✅' : '❌';
      const responseTime = `${result.responseTime}ms`;

      if (result.status === 'success') {
        console.log(`  ${statusIcon} ${result.url} - Block: ${result.blockNumber} (${responseTime})`);
      } else {
        console.log(`  ${statusIcon} ${result.url} - Error: ${result.error} (${responseTime})`);
      }
    }

    console.log('');
  }

  // Summary
  const successful = results.filter(r => r.status === 'success').length;
  const failed = results.filter(r => r.status === 'error').length;
  const avgResponseTime = Math.round(
    results.filter(r => r.status === 'success')
           .reduce((sum, r) => sum + r.responseTime, 0) /
    successful
  );

  console.log('=== VALIDATION SUMMARY ===');
  console.log(`Total endpoints tested: ${results.length}`);
  console.log(`✅ Successful: ${successful}`);
  console.log(`❌ Failed: ${failed}`);
  console.log(`⏱️  Average response time: ${avgResponseTime}ms`);

  if (failed > 0) {
    console.log('\n=== FAILED ENDPOINTS ===');
    results.filter(r => r.status === 'error').forEach(r => {
      console.log(`${r.chainName} (${r.chainId}): ${r.error}`);
    });
  }

  return results;
}

if (require.main === module) {
  validateAllRpcs().catch(console.error);
}

module.exports = { validateAllRpcs, validateRpcEndpoint };