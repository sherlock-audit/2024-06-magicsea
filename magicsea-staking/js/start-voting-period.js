const { AddressZero } = require('@ethersproject/constants')
const { JsonRpcProvider } = require('@ethersproject/providers')
const { formatEther, parseEther } = require('@ethersproject/units')
const voterABI = require('../out/Voter.sol/Voter.json').abi
const farmLensABI = require('../out/FarmLens.sol/FarmLens.json').abi
const masterChefABI = require('../out/src/MasterChefV2.sol/MasterChef.json').abi
const pairABI = require('../out/IMagicSeaPair.sol/IMagicSeaPair.json').abi
const { ethers } = require('ethers')

require('dotenv').config()

const FARM_LENS_TESTNET = "0x97635fc30c89D35F60ae997081cE321251406239";
const MASTERCHEF_TESTNET = "0x9112a7Ae4a5f03aC1CB1306de3a591fCa380816D";
const VOTER_TESTNET = "0xad9E54D5293D0bE0454e7903D8e07113F77aC7A3";


const provider = new JsonRpcProvider(process.env.RPC_IOTA_TESTNET_URL);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const voter = new ethers.Contract(VOTER_TESTNET, voterABI, signer)


async function main () {

    const now = Math.floor(Date.now() / 1000)

    // check if current voting period ended
    const currentPeriod = await voter.getCurrentVotingPeriod();
    const [startTime, endTime] = await voter.getPeriodStartEndtime(currentPeriod)

    const hasPeroiodEnded = now > endTime

    if (hasPeroiodEnded) {  

        console.log(`Starting new voting period`)
        await (
            await voter.startNewVotingPeriod()
        ).wait()
    }
}

main().catch( err => console.log(err))