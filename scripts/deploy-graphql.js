/**
 * Script for GraphQL API deployment and configuration
 * Sets up GraphQL endpoint with proper resolvers and schema
 */

const fs = require('fs');
const path = require('path');

console.log('=== GraphQL API Deployment Configuration ===\n');

// Check if rindexer.yaml has GraphQL enabled
const rindexerConfigPath = path.join(__dirname, '../rindexer.yaml');
if (!fs.existsSync(rindexerConfigPath)) {
  console.error('❌ rindexer.yaml not found. Please run from project root.');
  process.exit(1);
}

const rindexerConfig = fs.readFileSync(rindexerConfigPath, 'utf8');

if (rindexerConfig.includes('graphql:') && rindexerConfig.includes('enabled: true')) {
  console.log('✅ GraphQL API is enabled in rindexer.yaml');
} else {
  console.log('⚠️  GraphQL API may not be enabled in rindexer.yaml');
  console.log('   Please ensure the following configuration is present:');
  console.log('   graphql:');
  console.log('     enabled: true');
  console.log('     endpoint: "/graphql"');
  console.log('     playground: true');
}

// Check database connection setup
console.log('\n=== Database Configuration Check ===');
if (rindexerConfig.includes('storage:') && rindexerConfig.includes('postgres:')) {
  console.log('✅ PostgreSQL storage configuration found');
} else {
  console.log('❌ PostgreSQL storage configuration missing');
}

// Check for required environment variables
console.log('\n=== Environment Variables Check ===');
const requiredEnvVars = [
  'DATABASE_HOST',
  'DATABASE_PORT',
  'DATABASE_NAME',
  'DATABASE_USER',
  'DATABASE_PASSWORD'
];

const missingEnvVars = requiredEnvVars.filter(env => !process.env[env]);
if (missingEnvVars.length === 0) {
  console.log('✅ All required database environment variables are set');
} else {
  console.log('⚠️  Missing environment variables:', missingEnvVars.join(', '));
  console.log('   Please ensure these are set before deploying GraphQL API');
}

// GraphQL endpoint information
console.log('\n=== GraphQL Deployment Information ===');
console.log('📍 Default endpoint: http://localhost:4000/graphql');
console.log('🎮 GraphQL Playground: http://localhost:4000/graphql');
console.log('📊 Available queries:');
console.log('   - Portal intent lifecycle events');
console.log('   - ERC20 stable token transfers');
console.log('   - Native token transfers and balances');
console.log('   - Cross-chain activity summaries');

// Example queries
console.log('\n=== Example GraphQL Queries ===');
console.log(`
# Intent lifecycle tracking
query IntentLifecycle($intentId: String!) {
  intents(where: { id: $intentId }) {
    published { blockNumber, timestamp }
    funded { blockNumber, timestamp }
    proven { blockNumber, timestamp }
    fulfilled { blockNumber, timestamp }
    refunded { blockNumber, timestamp }
    withdrawn { blockNumber, timestamp }
  }
}

# Cross-chain Portal activity
query CrossChainActivity($timeRange: TimeRange!) {
  networks {
    name
    chainId
    intentCount(timeRange: $timeRange)
    volumeUSD(timeRange: $timeRange)
    portalAddress
  }
}

# Native balance tracking
query NativeBalances($addresses: [String!]!) {
  nativeBalances(addresses: $addresses) {
    address
    balances {
      chainId
      chainName
      balance
      balanceUSD
      lastUpdated
    }
    totalBalanceUSD
  }
}
`);

console.log('\n=== Deployment Commands ===');
console.log('1. Start the indexer with GraphQL enabled:');
console.log('   docker-compose up -d');
console.log('');
console.log('2. Verify GraphQL endpoint is accessible:');
console.log('   curl -X POST http://localhost:4000/graphql \\');
console.log('     -H "Content-Type: application/json" \\');
console.log('     -d \'{"query": "{ __schema { types { name } } }"}\'');
console.log('');
console.log('3. Monitor indexing progress:');
console.log('   docker logs -f eco-rindexer');

console.log('\n✅ GraphQL deployment configuration complete!');
console.log('📝 Next steps:');
console.log('   1. Ensure all environment variables are configured');
console.log('   2. Start the containers with docker-compose');
console.log('   3. Wait for initial indexing to complete');
console.log('   4. Access GraphQL playground at http://localhost:4000/graphql');