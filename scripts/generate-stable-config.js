/**
 * Generate comprehensive stable token configurations for rindexer.yaml
 * Based on @eco-foundation/chains stable token definitions
 */

const { EcoRoutesChains, EcoChains } = require('@eco-foundation/chains');

const ecoChains = new EcoChains({
  alchemyKey: '${ALCHEMY_API_KEY}',
  infuraKey: '${INFURA_API_KEY}',
  curtisKey: '${CURTIS_API_KEY}',
  mantaKey: '${MANTA_API_KEY}'
});

console.log('=== GENERATING STABLE TOKEN CONFIGURATIONS ===');

// Get all mainnet chains for stable token analysis
const mainnetChains = EcoRoutesChains.filter(chain => !chain.testnet).sort((a, b) => a.id - b.id);

// Aggregate all stable token data
const stableTokens = {};
let totalContracts = 0;

mainnetChains.forEach(chain => {
  const stables = ecoChains.getStablesForChain(chain.id);

  Object.entries(stables).forEach(([symbol, data]) => {
    if (!stableTokens[symbol]) {
      stableTokens[symbol] = [];
    }

    stableTokens[symbol].push({
      network: getNetworkName(chain.name),
      chainId: chain.id,
      chainName: chain.name,
      address: data.address,
      decimals: data.decimals,
      start_block: getStartBlock(chain.id, symbol)
    });

    totalContracts++;
  });
});

console.log(`Found ${Object.keys(stableTokens).length} stable token types`);
console.log(`Total contracts: ${totalContracts}`);

// Generate rindexer contract configurations
Object.entries(stableTokens).forEach(([symbol, deployments]) => {
  console.log(`\n=== ${symbol} Configuration (${deployments.length} chains) ===`);

  const contractConfig = {
    name: `Stable${symbol}`,
    details: deployments.map(deployment => ({
      network: deployment.network,
      address: deployment.address,
      start_block: deployment.start_block
    })),
    abi: './abis/tokens/ERC20.abi.json',
    include_events: ['Transfer']
  };

  console.log(`# ${symbol} - Deployed on ${deployments.length} chains`);
  console.log('  - name:', contractConfig.name);
  console.log('    details:');

  contractConfig.details.forEach(detail => {
    console.log(`      - network: ${detail.network}`);
    console.log(`        address: "${detail.address}"`);
    console.log(`        start_block: "${detail.start_block}"`);
  });

  console.log(`    abi: ${contractConfig.abi}`);
  console.log(`    include_events:`);
  contractConfig.include_events.forEach(event => {
    console.log(`      - ${event}`);
  });

  // Show chain distribution
  console.log(`\n  Chain distribution:`);
  deployments.forEach(d => {
    console.log(`    - ${d.chainName} (${d.chainId}): ${d.address}`);
  });
});

function getNetworkName(chainName) {
  return chainName.toLowerCase()
    .replace(/[^a-z0-9]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

function getStartBlock(chainId, symbol) {
  // Define appropriate start blocks for major chains and tokens
  const startBlocks = {
    // Ethereum start blocks
    1: {
      'USDC': '6082465',    // USDC deployment on Ethereum
      'USDT': '4634748',    // USDT deployment on Ethereum
      'oUSDT': '19000000',  // Origin USDT deployment
      'default': '18500000'
    },
    // Arbitrum start blocks
    42161: {
      'USDC': '150000000',
      'USDCe': '90000000',
      'USDT0': '150000000',
      'default': '150000000'
    },
    // Base start blocks
    8453: {
      'USDC': '8000000',
      'USDbC': '2000000',
      'oUSDT': '8000000',
      'default': '8000000'
    },
    // Polygon start blocks
    137: {
      'USDC': '45000000',
      'USDCe': '25000000',
      'USDT': '17000000',
      'default': '45000000'
    },
    // Optimism start blocks
    10: {
      'USDC': '105000000',
      'USDCe': '4300000',
      'USDT': '4300000',
      'oUSDT': '105000000',
      'default': '105000000'
    }
  };

  const chainBlocks = startBlocks[chainId];
  if (chainBlocks) {
    return chainBlocks[symbol] || chainBlocks.default;
  }

  // Default start blocks for other chains
  return '1';
}

console.log('\n=== STABLE TOKEN SUMMARY ===');
console.log(`Total stable token types: ${Object.keys(stableTokens).length}`);
Object.entries(stableTokens).forEach(([symbol, deployments]) => {
  console.log(`- ${symbol}: ${deployments.length} chains`);
});

console.log('\n=== NEXT STEPS ===');
console.log('1. Add the generated contract configurations to rindexer.yaml');
console.log('2. Test stable token indexing with a single token type');
console.log('3. Scale up to include all stable token types');
console.log('4. Monitor Transfer event volume and optimize accordingly');
