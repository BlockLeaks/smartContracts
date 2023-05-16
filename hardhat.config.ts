import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import * as dotenv from "dotenv";

dotenv.config();


const config: HardhatUserConfig = {
  solidity: "0.8.18",
  networks: {
    hardhat: {
        forking: {
            url: `https://eth-goerli.g.alchemy.com/v2/${process.env.ALCHEMY_PROJECT_ID}`,
        },
    },
    gnosis: {
        url: `https://gnosis.api.onfinality.io/public`,
        chainId: 100,
      accounts: [process.env.PRIVATE_KEY as string]
    },
    goerli: {
        url: `https://goerli.blockpi.network/v1/rpc/public`,
        chainId: 5,
      accounts: [process.env.PRIVATE_KEY as string]
    },
    mumbai: {
        url: `https://matic-mumbai.chainstacklabs.com`,
        chainId: 80001,
        accounts: [process.env.PRIVATE_KEY as string]
    },
  },
  
};





export default config;
