// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestERC721 is ERC721 {
    uint256 private _currentTokenId;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to) external {
        _currentTokenId++;
        _mint(to, _currentTokenId);
    }

    function mintBatch(address to, uint256 amount) external {
        for (uint256 i = 0; i < amount; i++) {
            _currentTokenId++;
            _mint(to, _currentTokenId);
        }
    }
}
