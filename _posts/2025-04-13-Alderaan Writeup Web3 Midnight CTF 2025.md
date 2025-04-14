---
title: Alderaan Writeup Web3 Midnight CTF 2025
date: 2025-04-13 21:01:02 +1
categories: [TOP_CATEGORIE, SUB_CATEGORIE]
categories: [CTF, Web3]
tags: [CTF, Writeup, Midnight, Web3]
---

## Looking at the Contract

Let's check out this smart contract challenge. The contract uses Solidity version 0.8.26, which means it has built-in safety features that prevent overflows and handle errors better.

## The contract code:  
```solidity
// Author : Neoreo
// Difficulty : Easy

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Alderaan {
    event AlderaanDestroyed(address indexed destroyer, uint256 amount);
    bool public isSolved = false;

    constructor() payable{
        require(msg.value > 0,"Contract require some ETH !");
    }

    function DestroyAlderaan(string memory _key) public payable {
        require(msg.value > 0, "Hey, send me some ETH !");
        require(
            keccak256(abi.encodePacked(_key)) == keccak256(abi.encodePacked("ObiWanCantSaveAlderaan")),
            "Incorrect key"
        );

        emit AlderaanDestroyed(msg.sender, address(this).balance);

        isSolved = true;
        selfdestruct(payable(msg.sender));
    }
}
```

The basic structure shows what we need to do:

```solidity
contract Alderaan {
    event AlderaanDestroyed(address indexed destroyer, uint256 amount);
    bool public isSolved = false;

    constructor() payable {
        require(msg.value > 0, "Contract require some ETH !");
    }
}
```

The constructor has a "payable" tag and requires some ETH to be sent when the contract is created. This tells us we're working with a contract that holds money.

## How to Destroy the Contract

The key to solving this challenge is in the DestroyAlderaan function:

```solidity
function DestroyAlderaan(string memory _key) public payable {
    require(msg.value > 0, "Hey, send me some ETH !");
    require(
        keccak256(abi.encodePacked(_key)) == keccak256(abi.encodePacked("ObiWanCantSaveAlderaan")),
        "Incorrect key"
    );

    emit AlderaanDestroyed(msg.sender, address(this).balance);
    isSolved = true;
    selfdestruct(payable(msg.sender));
}
```

This function does several interesting things. First, it compares strings using keccak256 hashing because Solidity can't compare strings directly. The `abi.encodePacked()` packs the data tightly before hashing, which uses less gas than `abi.encode()`.

## How to Solve It

To interact with this contract, we need to:
1. Send some ETH with our transaction
2. Use the exact string "ObiWanCantSaveAlderaan"
3. Make sure we format our data correctly

Here's the solution using cast (a tool from Foundry):

```bash
cast send $CONTRACT_ADDRESS "DestroyAlderaan(string)" "ObiWanCantSaveAlderaan" \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --chain-id $CHAIN_ID \
  --value 0.001ether
```

The function signature "DestroyAlderaan(string)" is important - it tells the contract how to decode our data. The value 0.001 ether can be any amount greater than zero.

## What selfdestruct Does

The most interesting part is the use of `selfdestruct`. This special command does two main things:
1. It sends all remaining ETH to the address you specify, bypassing any receive() or fallback() functions
2. It marks the contract for deletion, making its code unavailable for future blocks

Here's what happens when selfdestruct runs:

```solidity
selfdestruct(payable(msg.sender));
// 1. Sends all contract money to msg.sender
// 2. Empties the contract's code
// 3. Marks the contract for deletion
```

## Gas Efficiency

Using `keccak256` with `abi.encodePacked` for comparing strings saves gas. Here's why:

```solidity
// This way
keccak256(abi.encodePacked(_key))

// Uses less gas than
keccak256(abi.encode(_key))

// Because encodePacked removes extra padding and joins data directly
```

## The Event

The contract sends out an event when it's destroyed:

```solidity
event AlderaanDestroyed(address indexed destroyer, uint256 amount);
```

The `indexed` keyword on the destroyer address makes it easy to search for events by this address. The amount shows how much ETH was in the contract before it was destroyed, keeping a record of the funds.

## Checking If It Worked

To verify success, we can check the contract's isSolved status:

```bash
cast call $CONTRACT_ADDRESS "isSolved()(bool)" --rpc-url $RPC_URL
```

This should return true after we run our solution. But remember, after selfdestruct, while we can still read data from the current block, we can't interact with the contract anymore.

## How the Data is Formatted

When we send our transaction, the data looks like this:
- Function selector (4 bytes): First 4 bytes of keccak256("DestroyAlderaan(string)")
- String offset (32 bytes): Where the string data begins
- String length (32 bytes): How long our input string is
- String data (padded to 32 bytes): The actual string "ObiWanCantSaveAlderaan"

Understanding this helps us see why proper data formatting is important for successful contract interaction.

This challenge cleverly combines multiple Ethereum concepts: sending ETH, handling strings, destroying contracts, and emitting events, making it great for learning about smart contracts and security testing.

---

Thanks for reading, see ya !