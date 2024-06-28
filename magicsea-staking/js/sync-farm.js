const { AddressZero } = require('@ethersproject/constants')
const { JsonRpcProvider } = require('@ethersproject/providers')
const { formatEther, parseEther } = require('@ethersproject/units')
const voterABI = require('../out/Voter.sol/Voter.json').abi
const farmLensABI = require('../out/FarmLens.sol/FarmLens.json').abi
const masterChefABI = require('../out/src/MasterChefV2.sol/MasterChef.json').abi
const pairABI = require('../out/IMagicSeaPair.sol/IMagicSeaPair.json').abi
const { ethers } = require('ethers')

require('dotenv').config()

const FARM_LENS_TESTNET = "0x9A22c3f1bfd5f1E6e17079060ebeF355044adA2B";
const MASTERCHEF_TESTNET = "0x9112a7Ae4a5f03aC1CB1306de3a591fCa380816D";
const VOTER_TESTNET = "0xad9E54D5293D0bE0454e7903D8e07113F77aC7A3";


const provider = new JsonRpcProvider(process.env.RPC_IOTA_TESTNET_URL);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const voter = new ethers.Contract(VOTER_TESTNET, voterABI, signer)
const lens = new ethers.Contract(FARM_LENS_TESTNET, farmLensABI, provider)
const masterChef = new ethers.Contract(MASTERCHEF_TESTNET, masterChefABI, signer)


const voteLimit = process.env.VOTE_LIMIT || 1.5;

async function isUniPool (pool) {
    try {
        const magicseaPair = new ethers.Contract(pool, pairABI, provider)
        return await magicseaPair.token0() != AddressZero
    } catch(err) {
        return false
    }

}

async function getVotedPoolsAndPid() {
    const voteData = await lens.getVoteData(0, 100)
    const votedPools = voteData['votes'].map( (info) => {
        return {
            poolAddress: info[0],
            votes: parseFloat(formatEther(info[1]))
        }
    })
    .sort( (a, b) => a - b)

    const farmData = await lens.getFarmData(0,100, AddressZero)

    const farms = farmData['farms'].map( (raw) => {
        return {
            pool: raw['token'],
            pid: raw['pid']?.toString()
        }
    } )

    const votedPoolAndFarmPid = [...votedPools]
        .filter(p => p.votes >= voteLimit)
        .map((pool) => {
            const farm = farms.find((farm) => farm.pool == pool.poolAddress)
            return {
                ...pool,
                pid: farm?.pid
            }
        })

    return votedPoolAndFarmPid
}

async function main () {

    // sync voted pools and farm pids
    let votedPoolAndFarmPid = await getVotedPoolsAndPid()

    // create a farm where we have no pid
    const poolsWithoutPid = votedPoolAndFarmPid.filter( (pool) => !pool.pid)

    // create farms
    for(pool of poolsWithoutPid) {
        const isUniV2 = await isUniPool(pool.poolAddress)
        if (isUniV2) {
            console.log(`Adding pool [${pool.poolAddress}]`)

            await (
                await masterChef.add(pool.poolAddress, AddressZero)
            ).wait()
        }
    }

    // sync again
    votedPoolAndFarmPid = await getVotedPoolsAndPid()

    // filter all with pid
    const poolsWithPid = votedPoolAndFarmPid.filter( (pool) => !!pool.pid)

    console.log(poolsWithPid)


    const pids = poolsWithPid.map( (pool) => pool.pid)
    const weights = poolsWithPid.map( (pool) => parseEther(pool.votes.toString()))
    
    console.log(`Pids `, pids)
    console.log('Weights ', weights)

    // set weights on voter

    console.log(`Update old allocations on masterchef`)
    const oldPids = await voter.getTopPoolIds()
    await (
        await masterChef.updateAll(oldPids)
    ).wait()

    console.log(`Set weights and pids on voter`)
    await (
        await voter.setTopPoolIdsWithWeights(
            pids, weights
        )
    ).wait()

    console.log(`Update new allocations on masterchef`)
    await (
        await masterChef.updateAll(pids)
    ).wait()
}

main().catch( err => console.log(err))