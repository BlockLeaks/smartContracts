import { ethers } from "hardhat";

async function main() {

    const [deployer] = await ethers.getSigners();
    console.log("Deployer account:", deployer.address);

    const multisigAddress = "0x9090A5d516f2054007bD184caf55760B51fcFBfD"

    console.log(await deployer.getBalance());

    const BlockLeaks = await ethers.getContractFactory("BlockLeaks");
    const blockLeaks = await BlockLeaks.deploy(multisigAddress);

    await blockLeaks.deployed();

    console.log(
      `BlockLeaks: ${blockLeaks.address}`
    );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
