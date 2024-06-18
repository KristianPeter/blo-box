const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("Box Contract", function () {
    let Box, box, TestERC721, testERC721, owner, addr1, addr2;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy the TestERC721 contract
        TestERC721 = await ethers.getContractFactory("TestERC721");
        testERC721 = await TestERC721.deploy("Test ERC721", "T721");
        await testERC721.deployed();

        // Deploy the Box contract
        Box = await ethers.getContractFactory("Box");
        box = await upgrades.deployProxy(Box, [owner.address, "https://example.com/api/"], { initializer: 'initialize' });
        await box.deployed();

        // Grant roles to the owner
        const ADMIN_ROLE = await box.ADMIN_ROLE();
        await box.grantRole(ADMIN_ROLE, owner.address);
    });

    it("Should add ERC721 tokens to the Box contract", async function () {
        await testERC721.mint(owner.address);
        await testERC721.mint(owner.address);

        await testERC721.approve(box.address, 1);
        await testERC721.approve(box.address, 2);

        await box.connect(owner).depositERC721Tokens(testERC721.address, [1, 2]);

        expect(await testERC721.ownerOf(1)).to.equal(box.address);
        expect(await testERC721.ownerOf(2)).to.equal(box.address);
    });

    it("Should create two boxes", async function () {
        await testERC721.mint(owner.address);
        await testERC721.mint(owner.address);
        await testERC721.approve(box.address, 1);
        await testERC721.approve(box.address, 2);

        await box.connect(owner).depositERC721Tokens(testERC721.address, [1, 2]);

        const merkleRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test"));
        await box.connect(owner).createBoxes(2, 1, merkleRoot);

        expect(await box.totalSupply(0)).to.equal(1);
        expect(await box.totalSupply(1)).to.equal(1);
    });

    it("Should open boxes and distribute ERC721 tokens", async function () {
        await testERC721.mint(owner.address);
        await testERC721.mint(owner.address);
        await testERC721.approve(box.address, 1);
        await testERC721.approve(box.address, 2);

        await box.connect(owner).depositERC721Tokens(testERC721.address, [1, 2]);

        const merkleRoot = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test"));
        await box.connect(owner).createBoxes(2, 1, merkleRoot);

        const proof = []; // Assuming the proof is empty for simplicity in this example

        await box.connect(owner).openBox(0, 1, proof);
        await box.connect(owner).openBox(1, 1, proof);

        expect(await testERC721.ownerOf(1)).to.equal(owner.address);
        expect(await testERC721.ownerOf(2)).to.equal(owner.address);
    });
});
