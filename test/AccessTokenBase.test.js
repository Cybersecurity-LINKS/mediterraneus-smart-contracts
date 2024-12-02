const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");
//const { BN } = require('@openzeppelin/test-helpers');

const decimals = BigInt(10**18)
const totalSupply = decimals * BigInt(10);
const value = BigInt(5)*decimals;

describe('AccessTokenBase', function(){
    async function deployTokenFixture(){
        const [owner, addr1, addr2] = await ethers.getSigners();
    
        const AToken = await ethers.deployContract("AccessTokenBase");

        await AToken.initialize("name", "NM", owner, "0x11111111111111111111", "0x11111111111111111111", "0x11111111111111111111", 100);

        // Fixtures can return anything you consider useful for your tests
        return { AToken, owner, addr1, addr2 };
    }

    it('delegates', async function(){
        const {AToken, owner, addr1, addr2} = await loadFixture(deployTokenFixture);
        expect(await AToken.transferFrom(owner, addr1, 1)).to.be.true;
        expect(await AToken.setAccess(addr1)).to.not.reverted;
        expect(await AToken.canAccess(addr1, addr1)).to.be.true; 
        expect(await AToken.canAccess(addr1, addr2)).to.be.false; 
    })

    it('delegates', async function(){
        const {AToken, owner, addr1, addr2} = await loadFixture(deployTokenFixture);
        expect(await AToken.transferFrom(owner, addr1, 1)).to.be.true;
        expect(await AToken.setAccess(addr2)).to.not.reverted;
        expect(await AToken.canAccess(addr1, addr2)).to.be.true; 
        expect(await AToken.canAccess(addr1, addr1)).to.be.false; 
    })
})
