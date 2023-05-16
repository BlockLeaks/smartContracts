import { ethers } from "hardhat";

async function main() {

    const [deployer, multisig] = await ethers.getSigners();
    console.log("Deployer account:", deployer.address);

    /*const BlockLeaks = await ethers.getContractFactory("BlockLeaks");
    const blockLeaks = await BlockLeaks.deploy();

    await blockLeaks.deployed();

    console.log(
      `BlockLeaks: ${blockLeaks.address}`
    );
    
    let tx = await blockLeaks.writeMessage("0xa2977993e52606cfd67b7a1cde717069", "Hello", "Hello world");
    await tx.wait();
    tx = await blockLeaks.writeMessage("0xf4977993e52606cfee7b7a1cde717069", "Hi", "Hi world");
    await tx.wait();*/

    const blockLeaks = await attach("BlockLeaks", "0xe08aD9AE1EA062046F055ffa85381FEbF4548fa9");

    //await blockLeaks.writeMessage("0x0000", "0x00000000000000000000000000000002", "Hello", "Hello world", "Ici", {value: "10000000000000000"})
    //await blockLeaks.writeMessage("0x0000", "0x00000000000000000000000000000003", "Hello", "Hello world", "Ici", {value: "2000000000000000000"})
    //await blockLeaks.writeMessage("0x0000", "0x00000000000000000000000000000002", "Hello", "Hello world", "Ici", {value: "4000000000000000000"})
    console.log(await blockLeaks.messageCount());
    console.log("-------------------------------------------------------------")
    
    //await blockLeaks.connect(multisig).withdrawToMsgOwners([0, 2]);
    
    //await blockLeaks.connect(multisig).withdrawSomeToMultisig([1]);

    console.log(await blockLeaks.messages(0))
    //console.log(await blockLeaks.messages(1))
    //console.log(await blockLeaks.messages(2))
    
    console.log("-------------------------------------------------------------")

    console.log(await blockLeaks.getMessagesByGroupId("0x0dc019b57f99c040692d0e0da8e4c6ad"))

    console.log("-------------------------------------------------------------")

    console.log("MultisigBalance:", await deployer.getBalance());
    console.log("MultisigBalance:", await multisig.getBalance());
    
    
    
}

const attach = async (factory: any, address: any) => {
    let ContractFactory = await ethers.getContractFactory(factory);
    let contract = await ContractFactory.attach(address);
    console.log(factory, "has been load");
    return contract;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});