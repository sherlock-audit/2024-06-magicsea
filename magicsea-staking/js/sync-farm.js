const { AddressZero } = require('@ethersproject/constants')
const { JsonRpcProvider } = require('@ethersproject/providers')
const { formatEther, parseEther } = require('@ethersproject/units')
const voterABI = require('../out/Voter.sol/Voter.json').abi
const farmLensABI = require('../out/FarmLens.sol/FarmLens.json').abi
const masterChefABI = require('../out/src/MasterChefV2.sol/MasterChef.json').abi
const pairABI = require('../out/IMagicSeaPair.sol/IMagicSeaPair.json').abi
const lbHooksLensABI = require('./abi/lbHooksLens.json')
const lbHooksManagerABI = require('./abi/lbHooksManager.json')
const lbPairABI = require('./abi/lbPair.json')
const lbHooksMcRewarderABI = require('./abi/lbHooksMcRewarder.json')

const { ethers } = require('ethers')

require('dotenv').config()

const chainConfig = require("./config.json")

const config = chainConfig[process.env.CHAIN]

const FARM_LENS = config.farmLens;
const MASTERCHEF = config.masterChef;
const VOTER = config.voter;
const LB_HOOKS_MANAGER = config.lbHooksManager;
const LB_HOOKS_LENS = config.lbHooksLens;


const provider = new JsonRpcProvider(process.env.RPC_IOTA_TESTNET_URL);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const voter = new ethers.Contract(VOTER, voterABI, signer)
const lens = new ethers.Contract(FARM_LENS, farmLensABI, provider)
const masterChef = new ethers.Contract(MASTERCHEF, masterChefABI, signer)

const voteLimit = process.env.VOTE_LIMIT || 1.5;

async function isUniPool(pool) {
    try {
        const magicseaPair = new ethers.Contract(pool, pairABI, provider)
        return await magicseaPair.token0() != AddressZero
    } catch (err) {
        return false
    }

}

async function getVotedPoolsAndPid() {
    const voteData = await lens.getVoteData(0, 100)
    const votedPools = voteData['votes'].map((info) => {
        return {
            poolAddress: info[0],
            votes: parseFloat(formatEther(info[1]))
        }
    })
        .sort((a, b) => a - b)

    const farmData = await lens.getFarmData(0, 100, AddressZero)

    const farms = farmData['farms'].map((raw) => {
        return {
            pool: raw?.['poolInfo']?.['lbPair'] != AddressZero ? raw['poolInfo']['lbPair'] : raw['token'],
            pid: raw['pid']?.toString()
        }
    })

    const votedPoolAndFarmPid = [...votedPools]
        .filter(p => p.votes >= voteLimit)
        .map((pool) => {
            const farm = farms.find((farm) => 
                farm.pool == pool.poolAddress)
            return {
                ...pool,
                pid: farm?.pid
            }
        })

    return votedPoolAndFarmPid
}

async function createLbRewarder(pairAddress) {
    const lbHooksManager = new ethers.Contract(LB_HOOKS_MANAGER, lbHooksManagerABI, signer)
    const lbHooksLens = new ethers.Contract(LB_HOOKS_LENS, lbHooksLensABI, signer)
    const lbPair = new ethers.Contract(pairAddress, lbPairABI, signer)

    const hooks = await lbHooksLens.getHooks(pairAddress)

    if (hooks?.hooks == AddressZero) {
        console.log(`Creating rewarder for pool [${pairAddress}]`)

        const [tokenX, tokenY, binStep] = await Promise.all([
            lbPair.getTokenX(),
            lbPair.getTokenY(),
            lbPair.getBinStep()]
        )
        const [binStart, binEnd] = config.rewardRangePerBinStep[binStep] || config.defaultRange
        console.log(`Create Rewarder with ${pairAddress}, ${tokenX}, ${tokenY}, ${binStart}, ${binEnd}, ${binStep}`)

        await (
            await lbHooksManager.createLBHooksMCRewarder(tokenX, tokenY, binStep, signer.address)
        ).wait()

        const hooks = await lbHooksLens.getHooks(pairAddress)

        const lbHooksMcRewarder = new ethers.Contract(hooks?.hooks, lbHooksMcRewarderABI, signer)

        // set bin range
        console.log(`Set bin range for rewarder [${hooks?.hooks}]`)
        await (
            await lbHooksMcRewarder.setDeltaBins(binStart, binEnd)
        ).wait()

    } else {
        console.log(`Rewarder exists: `, hooks?.hooks)

        const [tokenX, tokenY, binStep] = await Promise.all([
            lbPair.getTokenX(),
            lbPair.getTokenY(),
            lbPair.getBinStep()]
        )
        const [binStart, binEnd] = config.rewardRangePerBinStep[binStep] || config.defaultRange

        const lbHooksMcRewarder = new ethers.Contract(hooks?.hooks, lbHooksMcRewarderABI, signer)

        // set bin range
        console.log(`Set bin range for rewarder [${hooks?.hooks}]`)
        await (
            await lbHooksMcRewarder.setDeltaBins(binStart, binEnd)
        ).wait()
    }
}

async function main() {

    // sync voted pools and farm pids
    let votedPoolAndFarmPid = await getVotedPoolsAndPid()

    // create a farm where we have no pid
    const poolsWithoutPid = votedPoolAndFarmPid.filter((pool) => !pool.pid)

    console.log(poolsWithoutPid)


    // create farms
    // for (pool of poolsWithoutPid) {
    //     const isUniV2 = await isUniPool(pool.poolAddress)
    //     if (isUniV2) {
    //         console.log(`Adding pool [${pool.poolAddress}]`)

    //         // await (
    //         //     await masterChef.add(pool.poolAddress, AddressZero)
    //         // ).wait()
    //     } else {
    //         console.log(`Adding LB rewarder pool [${pool.poolAddress}]`);
    //         // create rewarder
    //         await createLbRewarder(pool.poolAddress)

    //     }
    // }

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

main().catch(err => console.log(err))