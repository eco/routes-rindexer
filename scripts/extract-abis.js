/**
 * Script to extract ABIs from @eco-foundation/routes-ts package
 * Exports Portal ABI and creates ERC20 ABI for stable token monitoring
 */

const fs = require('fs');
const path = require('path');
const { PortalAbi } = require('@eco-foundation/routes-ts/dist/abi/contracts/Portal');

const abisDir = path.join(__dirname, '../abis');
const ecoRoutesDir = path.join(abisDir, 'eco-routes');
const tokensDir = path.join(abisDir, 'tokens');

// Ensure directories exist
[abisDir, ecoRoutesDir, tokensDir].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Write Portal ABI
console.log('Extracting Portal ABI...');
fs.writeFileSync(
  path.join(ecoRoutesDir, 'Portal.abi.json'),
  JSON.stringify(PortalAbi, null, 2)
);
console.log('Portal ABI written to abis/eco-routes/Portal.abi.json');

// Filter Portal events
const portalEvents = PortalAbi.filter(item => item.type === 'event');
console.log(`Portal ABI contains ${portalEvents.length} events:`);
portalEvents.forEach(event => {
  console.log(`  - ${event.name}`);
});

console.log('\nABI extraction completed successfully!');