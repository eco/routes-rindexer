/**
 * Generate comprehensive Portal contract configurations for rindexer.yaml
 * Based on @eco-foundation/routes-ts deployment addresses
 */

const { EcoRoutesChains, EcoChains } = require('@eco-foundation/chains');
const deployAddresses = require('@eco-foundation/routes-ts/deployAddresses.json');

console.log('=== GENERATING PORTAL CONTRACT CONFIGURATIONS ===');

// Get production deployments only (exclude staging)
const productionDeployments = Object.entries(deployAddresses).filter(([key]) => !key.includes('staging'));

console.log(`Found ${productionDeployments.length} production Portal deployments`);

// Group by Portal address
const portalGroups = {};
productionDeployments.forEach(([chainId, contracts]) => {
  if (contracts.Portal) {
    const portalAddress = contracts.Portal;
    if (!portalGroups[portalAddress]) {
      portalGroups[portalAddress] = [];
    }
    portalGroups[portalAddress].push({
      chainId: parseInt(chainId),
      address: portalAddress
    });
  }
});

console.log(`Portal addresses found: ${Object.keys(portalGroups).length}`);

// Generate rindexer configuration for each Portal address group
Object.entries(portalGroups).forEach(([portalAddress, deployments]) => {
  console.log(`\n=== Portal Address: ${portalAddress} (${deployments.length} chains) ===`);

  deployments.forEach(deployment => {
    const chain = EcoRoutesChains.find(c => c.id === deployment.chainId);
    if (chain) {
      const networkName = getNetworkName(chain.name);
      const startBlock = getStartBlock(deployment.chainId);

      console.log(`      - network: ${networkName}`);
      console.log(`        address: "${portalAddress}"`);
      console.log(`        start_block: "${startBlock}"`);
      console.log(`        # ${chain.name} (ID: ${deployment.chainId})`);
    } else {
      console.log(`      # Warning: Chain ID ${deployment.chainId} not found in EcoRoutesChains`);
    }
  });
});

// Generate complete Portal contract configuration
console.log('\n=== COMPLETE PORTAL CONTRACT CONFIGURATION ===');

let totalNetworks = 0;
const completeConfig = {
  name: 'Portal',
  details: [],
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
};

// Add all production deployments
productionDeployments.forEach(([chainId, contracts]) => {
  if (contracts.Portal) {
    const chainIdNum = parseInt(chainId);
    const chain = EcoRoutesChains.find(c => c.id === chainIdNum);

    if (chain) {
      const networkName = getNetworkName(chain.name);
      const startBlock = getStartBlock(chainIdNum);

      completeConfig.details.push({
        network: networkName,
        address: contracts.Portal,
        start_block: startBlock,
        comment: `${chain.name} (ID: ${chainIdNum})`
      });

      totalNetworks++;
    }
  }
});

console.log(`# Portal Contract - Complete Configuration (${totalNetworks} networks)`);
console.log('  - name: Portal');
console.log('    details:');
completeConfig.details.forEach(detail => {
  console.log(`      - network: ${detail.network}`);
  console.log(`        address: "${detail.address}"`);
  console.log(`        start_block: "${detail.start_block}"`);
  console.log(`        # ${detail.comment}`);
});

console.log(`    abi: ${completeConfig.abi}`);
console.log('    include_events:');
completeConfig.include_events.forEach(event => {
  console.log(`      - ${event}`);
});

console.log('\n=== PORTAL DEPLOYMENT STATISTICS ===');
Object.entries(portalGroups).forEach(([address, deployments]) => {
  console.log(`Portal ${address}:`);
  console.log(`  Deployments: ${deployments.length}`);
  deployments.forEach(d => {
    const chain = EcoRoutesChains.find(c => c.id === d.chainId);
    console.log(`    - ${chain ? chain.name : `Chain ${d.chainId}`} (${d.chainId})`);
  });
});

console.log('\n=== EVENT COVERAGE ANALYSIS ===');
console.log('Portal contract events indexed:');
completeConfig.include_events.forEach(event => {
  const eventDescriptions = {
    'IntentPublished': 'New intent creation',
    'IntentFulfilled': 'Intent completion',
    'IntentFunded': 'Intent funding',
    'IntentProven': 'Intent proof submission',
    'IntentRefunded': 'Intent refund processing',
    'IntentTokenRecovered': 'Token recovery',
    'IntentWithdrawn': 'Intent withdrawal',
    'OrderFilled': 'Order execution',
    'Open': 'Portal opening/activation',
    'EIP712DomainChanged': 'Domain updates'
  };

  console.log(`  - ${event}: ${eventDescriptions[event] || 'Event processing'}`);
});

function getNetworkName(chainName) {
  return chainName.toLowerCase()
    .replace(/[^a-z0-9]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

function getStartBlock(chainId) {
  // Define appropriate start blocks for Portal deployments
  const startBlocks = {
    1: '18500000',      // Ethereum - Portal deployment
    10: '105000000',    // Optimism
    56: '30000000',     // BSC
    130: '1',           // Unichain
    137: '45000000',    // Polygon
    146: '1',           // Sonic
    169: '1',           // Manta Pacific
    360: '1',           // Molten
    466: '1',           // Appchain
    478: '1',           // Form Network
    480: '1',           // World Chain
    1992: '1',          // Sanko Sepolia
    1996: '1',          // Sanko
    2525: '1',          // inEVM
    5000: '1',          // Mantle
    5330: '1',          // Superseed
    8333: '1',          // B3
    8453: '8000000',    // Base
    9745: '1',          // Plasma Mainnet
    33111: '1',         // Curtis
    33139: '1',         // Ape Chain
    42161: '150000000', // Arbitrum
    42220: '1',         // Celo
    57073: '1',         // Ink
    84532: '1',         // Base Sepolia
    3441006: '1',       // Manta Sepolia
    6524490: '1',       // Towns Sepolia
    10241024: '1',      // AlienX
    11155111: '1',      // Sepolia
    11155420: '1',      // OP Sepolia
    728126428: '1',     // Specialized chain
    1399811149: '1',    // Specialized chain
    1380012617: '1'     // Rari
  };

  return startBlocks[chainId] || '1';
}

console.log(`\n=== SUMMARY ===`);
console.log(`Total production Portal deployments: ${totalNetworks}`);
console.log(`Unique Portal addresses: ${Object.keys(portalGroups).length}`);
console.log(`Event types covered: ${completeConfig.include_events.length}`);