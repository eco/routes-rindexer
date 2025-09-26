# GraphQL API Documentation

This document describes the GraphQL API endpoints and schema for querying indexed Portal and stable token data.

## GraphQL Endpoint

- **URL**: `http://localhost:4000/graphql`
- **Playground**: `http://localhost:4000/graphql` (if enabled)

## Core Types

### Chain
```graphql
type Chain {
  id: Int!
  name: String!
  rpcUrl: String!
  blockNumber: BigInt
  isHealthy: Boolean!
  lastUpdated: DateTime
}
```

### Intent
```graphql
type Intent {
  hash: String!
  chainId: Int!
  creator: String!
  prover: String
  destinationChainId: Int
  rewardNativeAmount: BigInt
  status: IntentStatus!
  publishedAt: DateTime
  fundedAt: DateTime
  provenAt: DateTime
  fulfilledAt: DateTime
  withdrawnAt: DateTime
  refundedAt: DateTime
  events: [IntentEvent!]!
}

enum IntentStatus {
  PUBLISHED
  FUNDED
  PROVEN
  FULFILLED
  WITHDRAWN
  REFUNDED
}
```

### StableTransfer
```graphql
type StableTransfer {
  id: ID!
  chainId: Int!
  contractAddress: String!
  from: String!
  to: String!
  value: BigInt!
  blockNumber: BigInt!
  timestamp: DateTime!
  transactionHash: String!
  token: StableToken
}
```

### NativeBalance
```graphql
type NativeBalance {
  address: String!
  chainId: Int!
  balance: BigInt!
  symbol: String!
  lastUpdated: DateTime!
}
```

## Query Examples

### Intent Lifecycle Tracking
```graphql
query GetIntentLifecycle($intentHash: String!) {
  intent(hash: $intentHash) {
    hash
    chainId
    creator
    status
    publishedAt
    fundedAt
    provenAt
    fulfilledAt
    events {
      name
      blockNumber
      timestamp
      data
    }
  }
}
```

### Cross-Chain Portal Activity
```graphql
query GetCrossChainActivity($timeRange: TimeRange!) {
  chains {
    id
    name
    intentCount(timeRange: $timeRange)
    successRate(timeRange: $timeRange)
    avgProcessingTime(timeRange: $timeRange)
  }
}
```

### Native Token Balance Tracking
```graphql
query GetNativeBalances($addresses: [String!]!) {
  nativeBalances(addresses: $addresses) {
    address
    chainId
    balance
    symbol
    lastUpdated
  }
}
```

### Stable Token Analytics
```graphql
query GetStableTokenStats($tokenAddress: String!, $chainId: Int!) {
  stableToken(address: $tokenAddress, chainId: $chainId) {
    address
    symbol
    decimals
    totalSupply
    holderCount
    transfers(limit: 100) {
      from
      to
      value
      timestamp
    }
    topHolders(limit: 10) {
      address
      balance
      percentage
    }
  }
}
```

## Real-time Subscriptions

### Intent Status Updates
```graphql
subscription IntentStatusUpdates($intentHash: String) {
  intentStatusChanged(intentHash: $intentHash) {
    hash
    status
    timestamp
    event {
      name
      blockNumber
      data
    }
  }
}
```

### New Transfers
```graphql
subscription NewTransfers($chainId: Int, $tokenAddress: String) {
  transferAdded(chainId: $chainId, tokenAddress: $tokenAddress) {
    from
    to
    value
    timestamp
    transactionHash
  }
}
```