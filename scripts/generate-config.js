/**
 * Script to auto-generate rindexer.yaml configuration sections
 * Based on @eco-foundation/chains and @eco-foundation/routes-ts packages
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const { EcoRoutesChains, EcoChains } = require('@eco-foundation/chains');
const deployAddresses = require('@eco-foundation/routes-ts/deployAddresses.json');

const ecoChains = new EcoChains({
  alchemyKey: '${ALCHEMY_API_KEY}',
  infuraKey: '${INFURA_API_KEY}',
  curtisKey: '${CURTIS_API_KEY}',
  mantaKey: '${MANTA_API_KEY}'
});

console.log('Generating rindexer configuration...');

// Generate network configurations
const networks = [];
const mainnetChains = EcoRoutesChains.filter(chain => !chain.testnet).sort((a, b) => a.id - b.id);
const testnetChains = EcoRoutesChains.filter(chain => chain.testnet).sort((a, b) => a.id - b.id);

console.log(`Processing ${mainnetChains.length} mainnet chains and ${testnetChains.length} testnet chains...`);

[...mainnetChains, ...testnetChains].forEach(chain => {
  const rpcUrls = ecoChains.getRpcUrlsForChain(chain.id);
  const primaryRpc = rpcUrls[0];
  const fallbacks = rpcUrls.slice(1);

  const networkConfig = {
    name: chain.name.toLowerCase().replace(/[^a-z0-9]/g, '-'),
    chain_id: chain.id,
    rpc: primaryRpc
  };

  if (fallbacks.length > 0) {
    networkConfig.rpc_fallbacks = fallbacks;
  }

  networks.push(networkConfig);
});

// Generate Portal contract configurations
const portalContracts = [];
const productionDeployments = Object.entries(deployAddresses).filter(([key]) => !key.includes('staging'));

console.log(`Processing ${productionDeployments.length} Portal deployments...`);

productionDeployments.forEach(([chainId, contracts]) => {
  if (contracts.Portal) {
    const chainIdNum = parseInt(chainId);
    const chain = EcoRoutesChains.find(c => c.id === chainIdNum);

    if (chain) {
      portalContracts.push({
        network: chain.name.toLowerCase().replace(/[^a-z0-9]/g, '-'),
        address: contracts.Portal,
        start_block: getStartBlock(chainIdNum) // You'll need to define appropriate start blocks
      });
    }
  }
});

// Generate stable token configurations
const stableContracts = [];
const stableStats = {};

mainnetChains.forEach(chain => {
  const stables = ecoChains.getStablesForChain(chain.id);

  Object.entries(stables).forEach(([symbol, data]) => {
    if (!stableStats[symbol]) {
      stableStats[symbol] = [];
    }

    stableStats[symbol].push({
      network: chain.name.toLowerCase().replace(/[^a-z0-9]/g, '-'),
      address: data.address,
      start_block: getStartBlock(chain.id),
      decimals: data.decimals
    });
  });
});

// Convert stable stats to contract configurations
Object.entries(stableStats).forEach(([symbol, deployments]) => {
  stableContracts.push({
    name: `Stable${symbol}`,
    details: deployments,
    abi: './abis/tokens/ERC20.abi.json',
    include_events: ['Transfer']
  });
});

// Generate the configuration
const config = {
  name: 'eco-rindexer',
  description: 'Comprehensive indexer for Eco Foundation ecosystem across 34 EVM chains',
  project_type: 'no-code',

  networks: networks.slice(0, 5), // Start with first 5 networks for initial deployment

  contracts: [
    {
      name: 'Portal',
      details: portalContracts.slice(0, 5), // Start with first 5 Portal deployments
      abi: './abis/eco-routes/Portal.abi.json',
      include_events: [
        'IntentPublished',
        'IntentFulfilled',
        'IntentFunded',
        'IntentProven',
        'IntentRefunded',
        'IntentTokenRecovered',
        'IntentWithdrawn',
        'OrderFilled',
        'Open',
        'EIP712DomainChanged'
      ]
    },
    ...stableContracts.slice(0, 3) // Start with first 3 stable token types
  ],

  storage: {
    postgres: {
      enabled: true,
      host: '${DATABASE_HOST:-localhost}',
      port: '${DATABASE_PORT:-5432}',
      database: '${DATABASE_NAME:-eco_rindexer}',
      username: '${DATABASE_USER:-postgres}',
      password: '${DATABASE_PASSWORD}',
      pool_size: 20,
      max_connections: 100
    }
  },

  graphql: {
    enabled: true,
    endpoint: '/graphql',
    playground: true,
    max_query_depth: 10,
    max_query_complexity: 1000
  }
};

// Write the configuration
const configPath = path.join(__dirname, '../rindexer.yaml');
const yamlContent = yaml.dump(config, { indent: 2, lineWidth: -1 });

fs.writeFileSync(configPath, yamlContent);

console.log(`Configuration written to ${configPath}`);
console.log(`Networks configured: ${networks.length}`);
console.log(`Portal deployments: ${portalContracts.length}`);
console.log(`Stable token types: ${Object.keys(stableStats).length}`);

function getStartBlock(chainId) {
  // Define appropriate start blocks for major chains
  const startBlocks = {
    1: '18500000',      // Ethereum
    10: '105000000',    // Optimism
    56: '30000000',     // BSC
    137: '45000000',    // Polygon
    8453: '8000000',    // Base
    42161: '150000000', // Arbitrum
    // Add more as needed
  };

  return startBlocks[chainId] || '1';
}