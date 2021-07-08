const { ethers } = require("hardhat");
const { expect } = require("chai");
require("dotenv").config();
const { LeafKeyCoder, LeafValueCoder, constants } = require('@umb-network/toolbox');

// Chain registry address (see https://umbrella-network.readme.io/docs/umb-token-contracts)
const REGISTRY_CONTRACT_ADDRESS = process.env.REGISTRY_CONTRACT_ADDRESS;

describe("DefiPoolToken", function ()  {
  let DefiPoolToken, defiPool, MockDai, dai, priceRegistry, tx
  let daiUserBalance, daiContractBalance, LPBalanceOfUser

  const setup = async () => {
    [owner, alice] = await ethers.getSigners();
    DefiPoolToken = await ethers.getContractFactory("DefiPoolToken");
    MockDai = await ethers.getContractFactory("MockDai");
    console.log('owner', owner.address);
    priceRegistry = address(REGISTRY_CONTRACT_ADDRESS);
  }
  

  before(async () => {
    await setup();

    // Deploy the token contract, ideally it should be the real token taken as collateral, eg: DAI
    dai = await MockDai.deploy();
    await dai.deployed();

    // Deploy the Liquidity Pool smart contract
    defiPool = await DefiPoolToken.deploy(dai.address, address(priceRegistry), keyEncoder('DAI-BNB'));
    await defiPool.deployed();

    console.log('mock DAI token deployed at', dai.address);
    console.log('defiPool contract deployed at', defiPool.address);

  });
  
  it("Correctly sets DAI Underlyer and Price Aggregator", async () => {
    expect(await defiPool.underlyer()).to.equal(dai.address);
    expect(await defiPool.priceRegistry()).to.equal(address(priceRegistry));

    const keyPair = await defiPool.keyPair()
    console.log('keyPair', keyPair);
    expect(keyDecoder(keyPair)).to.equal('DAI-BNB');
  });
  
  it("Able to mint faucet tokens ", async () => {
    // Get some tokens, ideally it should be the real token taken as collateral, eg: DAI
    tx = await dai.connect(alice).faucet(parseUnits(50));
    await tx.wait()
    daiUserBalance = await dai.balanceOf(alice.address)
    expect(daiUserBalance).to.equal(parseUnits(50));
    console.log('dai balanceOf user', formatUnits(daiUserBalance));
  });

  it("Able to approve mockDai to the pool contract ", async () => {
    tx = await dai.connect(alice).approve(defiPool.address, parseUnits(50));
    await tx.wait()
    const allowance = await dai.allowance(alice.address, defiPool.address)
    expect(allowance).to.equal(parseUnits(50));
    
    console.log('dai allowance user', formatUnits(allowance));
  });

  it("Adding Liquidity", async () => {
    
    tx = await defiPool.connect(alice).addLiquidity(parseUnits(50));
    await tx.wait()

    // Check the balance of the Pool contract
    daiContractBalance = await dai.balanceOf(defiPool.address)
    expect(daiContractBalance).to.equal(parseUnits(50));
    
    // Check if user recieves the collateral backed tokens aka LP tokens
    LPBalanceOfUser = await defiPool.balanceOf(alice.address)
    expect(LPBalanceOfUser).to.gte(parseUnits(0));
    
    console.log('dai balance of the pool', formatUnits(daiContractBalance));
    console.log('LP balanceOf user', formatUnits(LPBalanceOfUser));
    
  })
  
  it("Redeeming Liquidity", async () => {
    // Able to redeem full supplied liquidity to get back underlyer
    tx = await defiPool.connect(alice).redeem(LPBalanceOfUser);
    await tx.wait();
    
    LPBalanceOfUser = await defiPool.balanceOf(alice.address)
    expect(LPBalanceOfUser).to.equal(parseUnits(0));
  })

  it("Able to fetch prices from Umbrella's oracles", async () => {
    const label = 'DAI-BNB'

    let price = await defiPool.getTokenBnbPrice()   // 1 DAI = ? BNB
    console.log('Price from Contract', price.toString());

    const priceAsNumber = valueDecoder(price, label);
    
    console.log('price As Number:', priceAsNumber);
    expect(priceAsNumber).to.gt(0.001).and.lt(0.005);   // Can Fail, but passing as of 08 July, 2021
  })
  

});

// Lsit of Helper functions
// Converts checksum
const address = (params) => {
  return ethers.utils.getAddress(params);
}

// Converts token units to smallest individual token unit, eg: 1 DAI = 10^18 units 
const parseUnits = (params) => {
  return ethers.utils.parseUnits(params.toString(), 18);
}

// Converts token units from smallest individual unit to token unit, opposite of parseUnits
const formatUnits = (params) => {
  return ethers.utils.formatUnits(params.toString(), 18);
}

// LeafKeyCoder => encode, string to convert into bytes32
const keyEncoder = (params) => {
  return LeafKeyCoder.encode(params)
}

// LeafKeyDeCoder => decode, bytes32 to convert into string
const keyDecoder = (params) => {
  return LeafKeyCoder.decode(params)
}


// LeafValueCoder => decode, price to number with label
const valueDecoder = (params, label) => {
  return LeafValueCoder.decode(params.toHexString(), label);
}