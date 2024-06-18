// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Box
 * @dev The Box contract allows for the creation of boxes containing ERC721 tokens. 
 * These boxes can be distributed to users who can then open them to receive random ERC721 tokens.
 * The contract uses AccessControl to manage roles and permissions.
 */
contract Box is Initializable, ERC1155PausableUpgradeable, AccessControlUpgradeable {
    uint256 public nextTokenIdToMint;
    mapping(uint256 => uint256) public totalSupply;
    mapping(uint256 => bytes32) public merkleRoots;
    IERC721[] public depositedERC721Tokens;
    uint256[] public depositedTokenIds;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event BoxCreated(uint256 indexed boxId, uint256 totalSupply);
    event BoxOpened(uint256 indexed boxId, address indexed opener, uint256 amount, bytes32[] proof);
    event TokensDeposited(address indexed depositor, address indexed tokenAddress, uint256 tokenId);
    event UnopenedBoxesRemoved(uint256 indexed boxId, uint256 amount);

    /**
     * @dev Initializes the contract setting the deployer as the initial admin.
     * @param admin The address of the initial admin.
     * @param uri The URI for the ERC1155 metadata.
     */
    function initialize(address admin, string memory uri) external initializer {
        __ERC1155_init(uri);
        __ERC1155Pausable_init();
        __AccessControl_init();
        _setRoleAdmin(ADMIN_ROLE, keccak256(abi.encodePacked(admin)));
    }

    /**
     * @dev Deposits ERC721 tokens into the contract for use in boxes.
     * @param tokenAddress The address of the ERC721 token contract.
     * @param tokenIds The IDs of the tokens to deposit.
     * @custom:dfk-heroes for depositing heroes, pets, weapons, and equipment.
     */
    function depositERC721Tokens(address tokenAddress, uint256[] calldata tokenIds) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(tokenAddress).transferFrom(msg.sender, address(this), tokenIds[i]);
            depositedERC721Tokens.push(IERC721(tokenAddress));
            depositedTokenIds.push(tokenIds[i]);
            emit TokensDeposited(msg.sender, tokenAddress, tokenIds[i]);
        }
    }

    /**
     * @dev Creates boxes with a specified number of tokens per box.
     * @param boxCount The number of boxes to create.
     * @param tokensPerBox The number of tokens each box should contain.
     * @param merkleRoot The Merkle root for validating proofs of box ownership.
     */
    function createBoxes(uint256 boxCount, uint256 tokensPerBox, bytes32 merkleRoot) external onlyRole(ADMIN_ROLE) {
        require(depositedTokenIds.length >= boxCount * tokensPerBox, "Not enough tokens to create boxes");

        for (uint256 i = 0; i < boxCount; i++) {
            uint256 boxId = nextTokenIdToMint++;
            totalSupply[boxId] = tokensPerBox;
            merkleRoots[boxId] = merkleRoot;

            _mint(msg.sender, boxId, 1, "");

            emit BoxCreated(boxId, 1);
        }
    }

    /**
     * @dev Opens a box and distributes its contents to the opener.
     * @param boxId The ID of the box to open.
     * @param amount The number of boxes to open.
     * @param proof The Merkle proof validating the opener's ownership of the box.
     */
    function openBox(uint256 boxId, uint256 amount, bytes32[] calldata proof) external whenNotPaused {
        require(balanceOf(msg.sender, boxId) >= amount, "Insufficient balance");
        require(_verify(merkleRoots[boxId], _leaf(msg.sender, amount), proof), "Invalid proof");

        _burn(msg.sender, boxId, amount);

        // Distribute random rewards
        _distributeRewards(msg.sender, boxId, amount);
        emit BoxOpened(boxId, msg.sender, amount, proof);
    }

    /**
     * @dev Removes unopened boxes and redistributes their contents back into the contract.
     * @param boxId The ID of the box to remove.
     * @param amount The number of boxes to remove.
     */
    function removeUnopenedBoxes(uint256 boxId, uint256 amount) external onlyRole(ADMIN_ROLE) {
        uint256 balance = balanceOf(msg.sender, boxId);
        require(balance >= amount, "Insufficient unopened boxes");

        _burn(msg.sender, boxId, amount);

        // Redistribute the rewards back into the contract
        _redistributeRewards(boxId, amount);
        emit UnopenedBoxesRemoved(boxId, amount);
    }

    /**
     * @dev Distributes the rewards from a box to the specified address.
     * @param to The address to receive the rewards.
     * @param boxId The ID of the box being opened.
     * @param amount The number of boxes being opened.
     */
    function _distributeRewards(address to, uint256 boxId, uint256 amount) internal {
        uint256 totalTokensToDistribute = totalSupply[boxId] * amount;
        for (uint256 i = 0; i < totalTokensToDistribute; i++) {
            require(depositedTokenIds.length > 0, "Not enough tokens to distribute");

            uint256 randomIndex = _getRandomIndex(depositedTokenIds.length);
            uint256 tokenId = depositedTokenIds[randomIndex];
            IERC721 tokenAddress = depositedERC721Tokens[randomIndex];

            _transferERC721(tokenAddress, to, tokenId);

            // Remove the token from the deposited arrays
            _removeToken(randomIndex);
        }
    }

    /**
     * @dev Redistributes the rewards from removed boxes back into the contract.
     * @param boxId The ID of the box being removed.
     * @param amount The number of boxes being removed.
     */
    function _redistributeRewards(uint256 boxId, uint256 amount) internal {
        uint256 totalTokensToRedistribute = totalSupply[boxId] * amount;
        for (uint256 i = 0; i < totalTokensToRedistribute; i++) {
            uint256 randomIndex = _getRandomIndex(depositedTokenIds.length);
            uint256 tokenId = depositedTokenIds[randomIndex];
            IERC721 tokenAddress = depositedERC721Tokens[randomIndex];

            depositedERC721Tokens.push(tokenAddress);
            depositedTokenIds.push(tokenId);
        }
    }

    /**
     * @dev Generates a leaf node for the Merkle tree.
     * @param account The account to include in the leaf.
     * @param amount The amount to include in the leaf.
     * @return The leaf node.
     */
    function _leaf(address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account, amount));
    }

    /**
     * @dev Verifies a Merkle proof.
     * @param root The Merkle root.
     * @param leaf The leaf node.
     * @param proof The Merkle proof.
     * @return True if the proof is valid, false otherwise.
     */
    function _verify(bytes32 root, bytes32 leaf, bytes32[] memory proof) internal pure returns (bool) {
        return MerkleProof.verify(proof, root, leaf);
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Generates a random index within the specified range.
     * @param max The upper bound for the random index.
     * @return A random index.
     */
    function _getRandomIndex(uint256 max) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % max;
    }

    /**
     * @dev Transfers an ERC721 token.
     * @param token The ERC721 token contract.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     */
    function _transferERC721(IERC721 token, address to, uint256 tokenId) internal {
        token.safeTransferFrom(address(this), to, tokenId);
    }

    /**
     * @dev Removes a token from the deposited arrays.
     * @param index The index of the token to remove.
     */
    function _removeToken(uint256 index) internal {
        require(index < depositedTokenIds.length, "Index out of bounds");

        uint256 lastIndex = depositedTokenIds.length - 1;
        if (index != lastIndex) {
            depositedTokenIds[index] = depositedTokenIds[lastIndex];
            depositedERC721Tokens[index] = depositedERC721Tokens[lastIndex];
        }

        depositedTokenIds.pop();
        depositedERC721Tokens.pop();
    }

    /**
     * @dev Withdraws ERC721 tokens from the contract.
     * @param to The address to withdraw the tokens to.
     * @param count The number of tokens to withdraw.
     */
    function withdrawERC721Tokens(address to, uint256 count) external onlyRole(ADMIN_ROLE) {
        require(depositedTokenIds.length >= count, "Not enough tokens to withdraw");

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = depositedTokenIds[i];
            IERC721 tokenAddress = depositedERC721Tokens[i];

            _transferERC721(tokenAddress, to, tokenId);
        }

        // Remove the tokens from the deposited arrays
        for (uint256 i = 0; i < count; i++) {
            _removeToken(0); // Always remove the first element
        }
    }

    /**
     * @dev Checks if the contract supports an interface.
     * @param interfaceId The interface identifier, as specified in ERC-165.
     * @return `true` if the contract implements `interfaceId`.
     */
    function supportsInterface(bytes4 interfaceId)
        public view override (ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
