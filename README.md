
# MagicSea contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
IotaEVM only
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Any type of ERC20 token. Pools are permissionless. So users can open pools even with weird tokens. Issues regarding any weird token will be valid if they have Med/High impact.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
No
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
Only owner modifier
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
N/A
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, arbitrage bots, etc.)?
We have an keeper for the Voting Epochs
___

### Q: Are there any hardcoded values that you intend to change before (some) deployments?
No
___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
Yes we are deploying on L2 IOTA - Yes please assume wont misbehave
___

### Q: Should potential issues, like broken assumptions about function behavior, be reported if they could pose risks in future integrations, even if they might not be an issue in the context of the scope? If yes, can you elaborate on properties/invariants that should hold?
No
___

### Q: Please discuss any design choices you made.
N/A
___

### Q: Please list any known issues and explicitly state the acceptable risks for each known issue.
N/A
___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
N/A
___

### Q: Please provide links to previous audits (if any).
First audit of this code still in progress
___

### Q: Please list any relevant protocol resources.
https://docs.magicsea.finance/
www.magicsea.finance

___

### Q: Additional audit information.
Could you please focus on the Voting & Bribing System
___



# Audit scope


[magicsea-staking @ fb97c8c92f6bca93d1a3184be625712c2fd3c994](https://github.com/metropolis-exchange/magicsea-staking/tree/fb97c8c92f6bca93d1a3184be625712c2fd3c994)
- [magicsea-staking/src/MasterchefV2.sol](magicsea-staking/src/MasterchefV2.sol)
- [magicsea-staking/src/MlumStaking.sol](magicsea-staking/src/MlumStaking.sol)
- [magicsea-staking/src/Voter.sol](magicsea-staking/src/Voter.sol)
- [magicsea-staking/src/interfaces/IBaseRewarder.sol](magicsea-staking/src/interfaces/IBaseRewarder.sol)
- [magicsea-staking/src/interfaces/IBribeRewarder.sol](magicsea-staking/src/interfaces/IBribeRewarder.sol)
- [magicsea-staking/src/interfaces/ILum.sol](magicsea-staking/src/interfaces/ILum.sol)
- [magicsea-staking/src/interfaces/IMagicSeaPair.sol](magicsea-staking/src/interfaces/IMagicSeaPair.sol)
- [magicsea-staking/src/interfaces/IMagicSeaRouter01.sol](magicsea-staking/src/interfaces/IMagicSeaRouter01.sol)
- [magicsea-staking/src/interfaces/IMagicSeaRouter02.sol](magicsea-staking/src/interfaces/IMagicSeaRouter02.sol)
- [magicsea-staking/src/interfaces/IMasterChef.sol](magicsea-staking/src/interfaces/IMasterChef.sol)
- [magicsea-staking/src/interfaces/IMasterChefRewarder.sol](magicsea-staking/src/interfaces/IMasterChefRewarder.sol)
- [magicsea-staking/src/interfaces/IMlumStaking.sol](magicsea-staking/src/interfaces/IMlumStaking.sol)
- [magicsea-staking/src/interfaces/IRewarder.sol](magicsea-staking/src/interfaces/IRewarder.sol)
- [magicsea-staking/src/interfaces/IRewarderFactory.sol](magicsea-staking/src/interfaces/IRewarderFactory.sol)
- [magicsea-staking/src/interfaces/IVoter.sol](magicsea-staking/src/interfaces/IVoter.sol)
- [magicsea-staking/src/interfaces/IVoterPoolValidator.sol](magicsea-staking/src/interfaces/IVoterPoolValidator.sol)
- [magicsea-staking/src/interfaces/IWNATIVE.sol](magicsea-staking/src/interfaces/IWNATIVE.sol)
- [magicsea-staking/src/libraries/Amounts.sol](magicsea-staking/src/libraries/Amounts.sol)
- [magicsea-staking/src/libraries/Clone.sol](magicsea-staking/src/libraries/Clone.sol)
- [magicsea-staking/src/libraries/Constants.sol](magicsea-staking/src/libraries/Constants.sol)
- [magicsea-staking/src/libraries/ImmutableClone.sol](magicsea-staking/src/libraries/ImmutableClone.sol)
- [magicsea-staking/src/libraries/Math.sol](magicsea-staking/src/libraries/Math.sol)
- [magicsea-staking/src/libraries/Rewarder.sol](magicsea-staking/src/libraries/Rewarder.sol)
- [magicsea-staking/src/libraries/Rewarder2.sol](magicsea-staking/src/libraries/Rewarder2.sol)
- [magicsea-staking/src/rewarders/BaseRewarder.sol](magicsea-staking/src/rewarders/BaseRewarder.sol)
- [magicsea-staking/src/rewarders/BribeRewarder.sol](magicsea-staking/src/rewarders/BribeRewarder.sol)
- [magicsea-staking/src/rewarders/MasterChefRewarder.sol](magicsea-staking/src/rewarders/MasterChefRewarder.sol)
- [magicsea-staking/src/rewarders/RewarderFactory.sol](magicsea-staking/src/rewarders/RewarderFactory.sol)

