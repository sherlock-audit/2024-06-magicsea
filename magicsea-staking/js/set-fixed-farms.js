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

const provider = new JsonRpcProvider(config.rpcUrl);
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

const voter = new ethers.Contract(VOTER, voterABI, signer)
const lens = new ethers.Contract(FARM_LENS, farmLensABI, provider)
const masterChef = new ethers.Contract(MASTERCHEF, masterChefABI, signer)


const lpTokens = {
    "iota" : [
        {
            token: "0x8f9a72d8f56479903ae386849e290d49389e41f9", // USDC-IOTA v2
            weight: "3904",
        },
        {
            token: "0xa4a8ef658ae0dbcca558e0b2dbd9e51925180d32", // ETH-IOTA v2
            weight: "2602",
        },
        {
            token: "0xa687eddac2648337492f37a182ca555e7e62b72a", // LUM-IOTA v2
            weight: "976"
        },
        {
            token: "0xb895f2be2347c244f202ca4b86db3a6722b10756", // MLUM-IOTA v2
            weight: "1952"
        },
        {
            token: "0x1C95009B4312bfBfbf340EF3224F30E16B774533", // SMR-IOTA v2
            weight: "488"
        },
        {
            token: "0xe919092cc7cbd2097ae3158f72da484ac813b74b", // USDT-USDC LB
            weight: "13"
        },
        {
            token: "0xa86d3169d5cccdc224637adad34f4f1be174000c", // USDC-IOTA LB
            weight: "39"
        },
        {
            token: "0xbac6c7808c453e988163283eb71e876cb325a3ee", // ETH-IOTA LB
            weight: "26"
        }
    ]
}

const lpTokensWithWeight = lpTokens[process.env.CHAIN]

async function isUniPool(pool) {
    try {
        const magicseaPair = new ethers.Contract(pool, pairABI, provider)
        return await magicseaPair.token0() != AddressZero
    } catch (err) {
        return false
    }

}

async function getPoolsAndPid() {
    const farmData = await lens.getFarmData(0, 100, AddressZero)

    const farms = farmData['farms'].map((raw) => {
        return {
            pool: raw?.['poolInfo']?.['lbPair'] != AddressZero ? raw['poolInfo']['lbPair'] : raw['token'],
            pid: raw['pid']?.toString()
        }
    })


    const poolsAndFarmPid = lpTokensWithWeight.map((pool) => {
            const farm = farms.find((farm) =>
                farm.pool?.toLowerCase() == pool.token?.toLowerCase())
            return {
                ...pool,
                pid: farm?.pid
            }
        })

    return poolsAndFarmPid
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
    let poolsAndFarmPid = await getPoolsAndPid()

    // create a farm where we have no pid
    const poolsWithoutPid = poolsAndFarmPid.filter((pool) => !pool.pid)

    console.log(poolsWithoutPid)


    // create farms
    for (pool of poolsWithoutPid) {
        const isUniV2 = await isUniPool(pool.token)
        if (isUniV2) {
            console.log(`Adding pool [${pool.token}]`)
            // await (
            //     await masterChef.add(pool.token, AddressZero)
            // ).wait()
        } else {
            console.log(`Adding LB rewarder pool [${pool.token}]`);
            // create rewarder
          await createLbRewarder(pool.token)

        }
    }

    // sync again
    poolsAndFarmPid = await getPoolsAndPid()

    // filter all with pid
    const poolsWithPid = poolsAndFarmPid.filter( (pool) => !!pool.pid)

    console.log(poolsWithPid)


    const pids = poolsWithPid.map( (pool) => pool.pid)
    const weights = poolsWithPid.map( (pool) => parseEther(pool.weight.toString()))

    console.log(`Pids `, pids)
    console.log('Weights ', weights)

    // set weights on voter
    console.log(`Update all allocations on masterchef`)
    // const oldPids = await voter.getTopPoolIds()
    await (
        await masterChef.updateAll(pids)
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