require("dotenv").config()
require("@nomiclabs/hardhat-waffle")
require("@nomiclabs/hardhat-etherscan")
require("@nomiclabs/hardhat-ethers");

const accounts = [process.env.DEV_PK]
module.exports = {
  networks: {
    hardhat: {},
    fantom: {
      url: "https://rpc.ftm.tools",
      accounts: accounts,
      gasMultiplier: 2
    }
  },
  solidity: {
    compilers: [{
      version: "0.6.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }, {
      version: "0.8.7",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }]
  },
}