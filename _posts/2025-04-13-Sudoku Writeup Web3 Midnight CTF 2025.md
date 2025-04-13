---
title: Sudoku Writeup Web3 Midnight CTF 2025
date: 2025-04-13 21:21:33 +1
categories: [TOP_CATEGORIE, SUB_CATEGORIE]
categories: [CTF, Web3]
tags: [CTF, Writeup, Midnight, Web3]
---

# Sublocku - Smart Contract Sudoku Challenge Writeup

## Introduction

The Sublocku challenge shows how Sudoku validation works on the Ethereum blockchain. This challenge mixes blockchain development, storage handling, and puzzle-solving code. What makes it cool is how it uses Ethereum's storage patterns to run a game.

## The contract: 
```solidity
// Author : Neoreo
// Difficulty : Medium

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Sublocku {

    uint private size;
    uint256[][] private game;
    bool public isSolved = false;

    address public owner;
    address public lastSolver;


    constructor(uint256 _size,uint256[][] memory initialGrid) {
        owner = msg.sender;
        size = _size;
        require(initialGrid.length == size, "Grid cannot be empty");
        for (uint i = 0; i < size; i++) {
            require(initialGrid[i].length == size, "Each row must have the same length as the grid");
        }
        game = initialGrid;
    }


    function unlock(uint256[][] memory solve) public {

        require(solve.length == size, "Solution grid size mismatch");
        for (uint i = 0; i < size; i++) {
            require(solve[i].length == size, "Solution grid row size mismatch");
        }

        for (uint i = 0; i < size; i++) {
            for (uint j = 0; j < size; j++) {
                if (game[i][j] != 0) {
                    require(game[i][j] == solve[i][j], "Cannot modify initial non-zero values");
                }
            }
        }

        require(checkRows(solve),    "Row validation failed");
        require(checkColumns(solve), "Column validation failed");
        require(checkSquares(solve), "Square validation failed");
        lastSolver = tx.origin;
    }

    function checkRows(uint256[][] memory solve) private view returns (bool){
        uint256[] memory available;
        uint256 val;
        for (uint i = 0; i < size; i++) {
            available = values();
            for (uint j = 0; j < size; j++) {
                val = solve[i][j];
                if (val <= 0 || val > size){
                    return false;
                }   
                if (available[val-1] == 0){
                    return false;
                }
                available[val-1] = 0;
            }
            if (sum(available) != 0) {
                return false;
            }
        }
        return true;
    }


    function checkColumns(uint256[][] memory solve) private view returns (bool){
        uint256[] memory available;
        uint256 val;
        for (uint i = 0; i < size; i++) {
            available = values();
            for (uint j = 0; j < size; j++) {
                val = solve[j][i];
                if (val <= 0 || val > 9){
                    return false;
                }   
                if (available[val-1] == 0){
                    return false;
                }
                available[val-1] = 0;
            }

            if (sum(available) != 0) {
                return false;
            }
        }
        return true;
    }

    function checkSquares(uint256[][] memory solve) private view returns (bool) {
        uint256[] memory available;
        uint256 val;

        for (uint startRow = 0; startRow < size; startRow += 3) {
            for (uint startCol = 0; startCol < size; startCol += 3) {
                available = values();

                for (uint i = 0; i < 3; i++) {
                    for (uint j = 0; j < 3; j++) {
                        val = solve[startRow + i][startCol + j];
                        if (val <= 0 || val > 9) {
                            return false;
                        }
                        if (available[val-1] == 0) {
                            return false;
                        }
                        available[val-1] = 0;
                    }
                }

                if (sum(available) != 0) {
                    return false;
                }
            }
        }
        return true;
    }


    function values() internal pure returns (uint256[] memory){
        uint256[] memory available_values = new uint256[](9);
        available_values[0] = uint256(1);
        available_values[1] = uint256(2);
        available_values[2] = uint256(3);
        available_values[3] = uint256(4);
        available_values[4] = uint256(5);
        available_values[5] = uint256(6);
        available_values[6] = uint256(7);
        available_values[7] = uint256(8);
        available_values[8] = uint256(9);
        return available_values;
    }

    function sum(uint256[] memory array) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < array.length; i++) {
            total += array[i];
        }
        return total;
    }
}
```

## Looking at the Code

### Main Contract (Sublocku.sol)

Let's check out the main parts of the contract:

```solidity
contract Sublocku {
    uint private size;
    uint256[][] private game;
    bool public isSolved = false;
    address public owner;
    address public lastSolver;
}
```

The contract uses a two-dimensional array (`uint256[][]`) for the game board, which creates interesting storage patterns on the blockchain. Let's look at the key parts:

#### How it Checks Sudoku Rules
The contract has three types of checks, each handling a different part of Sudoku rules:

```solidity
function checkRows(uint256[][] memory solve) private view returns (bool) {
    uint256[] memory available;
    uint256 val;
    for (uint i = 0; i < size; i++) {
        available = values();
        for (uint j = 0; j < size; j++) {
            val = solve[i][j];
            if (val <= 0 || val > size){
                return false;
            }   
            if (available[val-1] == 0){
                return false;
            }
            available[val-1] = 0;
        }
        if (sum(available) != 0) {
            return false;
        }
    }
    return true;
}
```

This row checking function is smart because:
1. It uses the `available` array like a checklist
2. It makes sure numbers are valid (`val <= 0 || val > size`)
3. It makes sure no number appears twice
4. It checks that all numbers 1-9 are used by checking the sum

### Reading the Storage (GetSublocku.s.sol)

First, we need to see what the grid looks like, so we create a contract for that:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract GetSublocku is Script {
    address public challenge = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    
    function run() external view {
        // Get the size - slot 0
        bytes32 sizeData = vm.load(challenge, bytes32(uint256(0)));
        uint256 size = uint256(sizeData);
        console.log("Game size:", size);
        
        // The game variable starts at slot 1
        // For dynamic arrays of arrays, the slot holds the length of the outer array
        bytes32 gameDataLength = vm.load(challenge, bytes32(uint256(1)));
        console.log("External array length:", uint256(gameDataLength));
        
        // The hash of this slot contains the location of the actual array
        bytes32 location = keccak256(abi.encode(1));
        
        // Show the grid
        console.log("Initial game grid:");
        for (uint i = 0; i < size; i++) {
            // For each row, first get the length
            bytes32 rowLocation = bytes32(uint256(location) + i);
            bytes32 rowDataLocation = keccak256(abi.encode(rowLocation));
            
            string memory rowStr = "";
            for (uint j = 0; j < size; j++) {
                bytes32 cellData = vm.load(challenge, bytes32(uint256(rowDataLocation) + j));
                uint256 cellValue = uint256(cellData);
                
                if (j > 0) rowStr = string(abi.encodePacked(rowStr, ", "));
                rowStr = string(abi.encodePacked(rowStr, vm.toString(cellValue)));
            }
            console.log("[%s]", rowStr);
        }
    }
}
```

The grid doesn't change between runs, so we can hardcode it in the solver script.

This storage reading script shows how Ethereum stores data:

```solidity
contract GetSublocku is Script {
    address public challenge = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    
    function run() external view {
        bytes32 sizeData = vm.load(challenge, bytes32(uint256(0)));
        uint256 size = uint256(sizeData);
        
        bytes32 gameDataLength = vm.load(challenge, bytes32(uint256(1)));
        bytes32 location = keccak256(abi.encode(1));
```

This script shows advanced blockchain concepts:
1. Reading storage slots directly with `vm.load`
2. Understanding how dynamic arrays are stored
3. Using `keccak256` to find storage locations

The coolest part is how it rebuilds the grid:

```solidity
for (uint i = 0; i < size; i++) {
    bytes32 rowLocation = bytes32(uint256(location) + i);
    bytes32 rowDataLocation = keccak256(abi.encode(rowLocation));
    
    string memory rowStr = "";
    for (uint j = 0; j < size; j++) {
        bytes32 cellData = vm.load(challenge, bytes32(uint256(rowDataLocation) + j));
        uint256 cellValue = uint256(cellData);
```

This shows how nested arrays are stored in Solidity:
1. The length of the outer array is at slot 1
2. The actual data location is found using `keccak256`
3. Each inner array has its own storage pattern

### Solver Code (SolveSublocku.s.sol)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface ISublocku {
    function unlock(uint256[][] memory solve) external;
    function isSolved() external view returns (bool);
    function lastSolver() external view returns (address);
}

contract SolveSublocku is Script {
    address public challenge = 0x685215B6aD89715Ef72EfB820C13BFa8E024401a;
    
    function run() external {
        // Initialize the grid we found
        uint256[][] memory grid = new uint256[][](9);
        
        grid[0] = new uint256[](9);
        grid[0][0] = 3; grid[0][1] = 1; grid[0][2] = 7; grid[0][3] = 4; grid[0][4] = 9; 
        grid[0][5] = 5; grid[0][6] = 0; grid[0][7] = 8; grid[0][8] = 2;
        
        grid[1] = new uint256[](9);
        grid[1][0] = 9; grid[1][1] = 2; grid[1][2] = 6; grid[1][3] = 3; grid[1][4] = 1; 
        grid[1][5] = 8; grid[1][6] = 7; grid[1][7] = 5; grid[1][8] = 4;
        
        grid[2] = new uint256[](9);
        grid[2][0] = 5; grid[2][1] = 4; grid[2][2] = 8; grid[2][3] = 7; grid[2][4] = 2; 
        grid[2][5] = 6; grid[2][6] = 3; grid[2][7] = 1; grid[2][8] = 9;
        
        grid[3] = new uint256[](9);
        grid[3][0] = 4; grid[3][1] = 3; grid[3][2] = 1; grid[3][3] = 8; grid[3][4] = 0; 
        grid[3][5] = 7; grid[3][6] = 9; grid[3][7] = 2; grid[3][8] = 6;
        
        grid[4] = new uint256[](9);
        grid[4][0] = 6; grid[4][1] = 9; grid[4][2] = 2; grid[4][3] = 1; grid[4][4] = 3; 
        grid[4][5] = 4; grid[4][6] = 8; grid[4][7] = 7; grid[4][8] = 5;
        
        grid[5] = new uint256[](9);
        grid[5][0] = 8; grid[5][1] = 7; grid[5][2] = 5; grid[5][3] = 9; grid[5][4] = 6; 
        grid[5][5] = 2; grid[5][6] = 4; grid[5][7] = 3; grid[5][8] = 1;
        
        grid[6] = new uint256[](9);
        grid[6][0] = 7; grid[6][1] = 8; grid[6][2] = 9; grid[6][3] = 5; grid[6][4] = 4; 
        grid[6][5] = 1; grid[6][6] = 2; grid[6][7] = 6; grid[6][8] = 3;
        
        grid[7] = new uint256[](9);
        grid[7][0] = 1; grid[7][1] = 0; grid[7][2] = 4; grid[7][3] = 2; grid[7][4] = 8; 
        grid[7][5] = 0; grid[7][6] = 5; grid[7][7] = 9; grid[7][8] = 7;
        
        grid[8] = new uint256[](9);
        grid[8][0] = 2; grid[8][1] = 5; grid[8][2] = 3; grid[8][3] = 6; grid[8][4] = 7; 
        grid[8][5] = 9; grid[8][6] = 1; grid[8][7] = 4; grid[8][8] = 8;
        
        // Show the starting grid
        console.log("Initial grid:");
        printGrid(grid);
        
        // Solve the Sudoku
        uint256[][] memory solution = solveSudoku(grid);
        
        // Show the solution
        console.log("Solution:");
        printGrid(solution);
        
        // Send the solution to the contract
        uint256 privateKey = 0x6f9b790c8f49db765ebf784eb62f17a2d5d5518bd7018544fcc9a42d80c5c3be;
        vm.startBroadcast(privateKey);
        
        ISublocku(challenge).unlock(solution);
        
        bool solved = ISublocku(challenge).isSolved();
        address lastSolver = ISublocku(challenge).lastSolver();
        
        console.log("Challenge solved:", solved);
        console.log("Last solver:", lastSolver);
        
        vm.stopBroadcast();
    }
    
    function printGrid(uint256[][] memory grid) internal view {
        for (uint i = 0; i < grid.length; i++) {
            string memory row = "";
            for (uint j = 0; j < grid[i].length; j++) {
                if (j > 0) row = string(abi.encodePacked(row, " "));
                row = string(abi.encodePacked(row, vm.toString(grid[i][j])));
            }
            console.log(row);
        }
    }
    
    function solveSudoku(uint256[][] memory grid) internal pure returns (uint256[][] memory) {
        uint256[][] memory solution = new uint256[][](9);
        for (uint i = 0; i < 9; i++) {
            solution[i] = new uint256[](9);
            for (uint j = 0; j < 9; j++) {
                solution[i][j] = grid[i][j];
            }
        }
        
        solve(solution, 0, 0);
        return solution;
    }
    
    function solve(uint256[][] memory grid, uint row, uint col) internal pure returns (bool) {
        // If we reached the end of the grid, solution is found
        if (row == 9) return true;
        
        // Move to next row if we reached the end of the column
        if (col == 9) return solve(grid, row + 1, 0);
        
        // If cell is already filled, move to the next one
        if (grid[row][col] != 0) return solve(grid, row, col + 1);
        
        // Try each possible value
        for (uint num = 1; num <= 9; num++) {
            if (isValid(grid, row, col, num)) {
                grid[row][col] = num;
                
                // Recursion
                if (solve(grid, row, col + 1)) {
                    return true;
                }
                
                // Backtracking if solution not found
                grid[row][col] = 0;
            }
        }
        
        return false;
    }
    
    function isValid(uint256[][] memory grid, uint row, uint col, uint num) internal pure returns (bool) {
        // Check row
        for (uint j = 0; j < 9; j++) {
            if (grid[row][j] == num) return false;
        }
        
        // Check column
        for (uint i = 0; i < 9; i++) {
            if (grid[i][col] == num) return false;
        }
        
        // Check 3x3 square
        uint startRow = (row / 3) * 3;
        uint startCol = (col / 3) * 3;
        
        for (uint i = 0; i < 3; i++) {
            for (uint j = 0; j < 3; j++) {
                if (grid[startRow + i][startCol + j] == num) return false;
            }
        }
        
        return true;
    }
} 
```

The solver script uses a backtracking method:

```solidity
function solve(uint256[][] memory grid, uint row, uint col) internal pure returns (bool) {
    if (row == 9) return true;
    if (col == 9) return solve(grid, row + 1, 0);
    if (grid[row][col] != 0) return solve(grid, row, col + 1);
    
    for (uint num = 1; num <= 9; num++) {
        if (isValid(grid, row, col, num)) {
            grid[row][col] = num;
            if (solve(grid, row, col + 1)) {
                return true;
            }
            grid[row][col] = 0;
        }
    }
    return false;
}
```

This code is neat because:
1. It uses recursion for backtracking
2. It handles grid edges well
3. It keeps existing numbers
4. It properly backtracks by resetting failed attempts

## How the Server Works

While our local testing used a grid with zeros, the actual server used a fixed grid with numbers. This matters because:

1. It changed our testing approach
2. It made our final solution simpler
3. It made the dynamic solver less important

Because the server always gave us the same grid, we could optimize our solution. But it's worth noting that the `SolveSublocku.s.sol` script includes a full solver that could handle any valid Sudoku grid.

## Understanding Storage Layout

Understanding how data is stored was key for this challenge. In Ethereum, storage slots are 32 bytes each, and arrays use a complex storage pattern:

1. Slot 0: Contract size variable
2. Slot 1: Length of the game array
3. Other slots: Found using `keccak256`

The 2D array follows this pattern:
```
slot[0] = size
slot[1] = length of outer array
slot[keccak256(1)] = length of first inner array
slot[keccak256(1) + 1] = first element of first inner array
...
```

## Ways to Improve

While our solution worked for the challenge, we could make it better:

### Better Solver
The current `SolveSublocku.s.sol` has a complete solver, but we didn't need to use it because the server always used the same grid. In a more changing environment, this solver would be valuable. The solver:

1. Tries numbers 1-9 in each empty cell
2. Checks each try against Sudoku rules
3. Goes back when it hits a dead end
4. Keeps going until it finds a valid solution

### Speed Improvements
The current checking functions could be faster:

```solidity
function checkSquares(uint256[][] memory solve) private view returns (bool) {
    uint256[] memory available;
    uint256 val;

    for (uint startRow = 0; startRow < size; startRow += 3) {
        for (uint startCol = 0; startCol < size; startCol += 3) {
            available = values();
```

This could be better by:
1. Using bit tricks instead of arrays
2. Combining checks
3. Adding early exits

## Conclusion

The Sublocku challenge shows how regular puzzles can work on a blockchain. It combines:

1. Smart contract coding
2. Storage patterns
3. Algorithm design
4. Speed improvements

While we used a simple solution because of how the server worked, the challenge shows you need to understand both theory (Sudoku algorithms) and practice (blockchain storage, gas saving) in smart contract development.

The best things we learned from this challenge were:
1. How Ethereum stores data
2. Creating check systems in smart contracts
3. Balancing between nice code and practical speed
4. Working with arrays in Solidity
5. Reading contract storage directly

This challenge connects regular programming and blockchain development, teaching useful things about both.

---

Thanks for reading, see ya !