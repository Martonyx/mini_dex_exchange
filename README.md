# Mini DEX Exchange

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity Version](https://img.shields.io/badge/Solidity-0.8.20-lightgrey.svg)](https://soliditylang.org/)

A decentralized exchange (DEX) implementation with core swapping and liquidity provision functionality, built on Ethereum.

## Features

- 🔄 Token swapping with adjustable slippage tolerance
- 💧 Add/remove liquidity from pools
- 📊 Spot price calculations
- 🔄 USYT token routing for indirect swaps
- 🔒 Reentrancy protection
- ⏳ Deadline-based transaction execution
- 💰 Automated fee distribution (0.3% total fee)

## Contracts

## Architecture

│ Factory  │───▶│ Pair │◀───│ Router │

                    ▲
                    │
                    ▼

            │ ERC20 Tokens │

### Component Relationships:
- **Factory**: Creates new Pair contracts
- **Pair**: Manages individual token pools (liquidity pools)
- **Router**: Main interface for users (swaps, liquidity management)
- **ERC20 Tokens**: External token contracts that interact with the DEX

### Router

The main entry point for all exchange operations. Handles:

- `addLiquidity`: Deposit tokens to create a new pool or add to an existing one
- `removeLiquidity`: Withdraw your liquidity from a pool
- `swapExactTokensForTokens`: Execute token swaps with exact input amounts
- `getSpotPrice`: Query current pool prices
- `getPairAddress`: Get the address of a token pair's pool

## Technical Details

### State Variables

| Parameter          | Value | Description                          |
|--------------------|-------|--------------------------------------|
| TOTAL_FEE          | 3     | 0.3% total trading fee               |
| DENOMINATOR        | 1000  | Fee calculation base                 |
| MAX_SLIPPAGE       | 1000  | Maximum allowed slippage (100%)      |
| MIN_SLIPPAGE       | 5     | Minimum allowed slippage (0.5%)      |

### Fee Structure

- Total fee: 0.3%
- Protocol fee portion: Configurable via Factory
- Remaining fee: Goes to liquidity providers

### Security Features

- Reentrancy guards on all external functions
- Input validation (zero address, identical tokens)
- Deadline checks for transactions
- Slippage protection
- Proper fee calculations using fixed-point math

## Installation

1. Install dependencies:
```bash
npm install @openzeppelin/contracts