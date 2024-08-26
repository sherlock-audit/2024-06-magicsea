// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title Constants Addresses
 * @dev This library contains addresses of the deployed contracts
 *  == Return ==
 * proxyAdmin: contract ProxyAdmin2Step 0x7f87289C5B0e1D6E8707432F7865412c10cb14D2
 * rewarders: contract IBaseRewarder[2] [0x3095613eAf5A62c93C0981f39B0b2Bb2C799eD13, 0x0000000000000000000000000000000000000000]
 * implementations: struct Deployer.SCAddresses SCAddresses({ rewarderFactory: 0x73b05F0D61F8d28520CD128471CB1ac3d89C4e17, masterChef: 0x9aD9A9f4dEFF57e8e54cdDc095503aeD00225436, voter: 0x509F6F5e0D19a28E359bcd5c5AA98216616C98ef })
 * proxies: struct Deployer.SCAddresses SCAddresses({ rewarderFactory: 0xcdCd9Da9901D40DEED65a03d51C8fD0256Bb0dDE, masterChef: 0xaEd6DC9B5AE8aC8149403D2659de1239655E6D4a, voter: 0x09c705b517E13F315dF82191E1FC9D210b6429E0 })
 */
library Addresses {
    address internal constant PROXY_ADMIN_MAINNET = 0x7f87289C5B0e1D6E8707432F7865412c10cb14D2;
    address internal constant LUM_MAINNET = 0x34a85ddc4E30818e44e6f4A8ee39d8CBA9A60fB3;
    address internal constant MLUM_MAINNET = 0xA87666b0Cb3631c49f96CBf1e6A52EBac79A6143;
    address internal constant REWARD_IOTA_TOKEN_MAINNET = 0xFbDa5F676cB37624f28265A144A48B0d6e87d3b6;

    address internal constant LENS_MAINNET = 0xE1D84B09969E34cD0C23836Ab30bDa31da422eB7;

    address internal constant PROXY_REWARDER_FACTORY_MAINNET = 0xcdCd9Da9901D40DEED65a03d51C8fD0256Bb0dDE;
    address internal constant PROXY_MASTERCHEF_MAINNET = 0xaEd6DC9B5AE8aC8149403D2659de1239655E6D4a;
    address internal constant PROXY_MLUM_STAKING_MAINNET = 0x1379eDC2771e73E3dE628EC308b418ce5e2D2bcc;
    address internal constant PROXY_VOTER_MAINNET = 0x09c705b517E13F315dF82191E1FC9D210b6429E0;

    address internal constant IMPL_REWARDER_FACTORY_MAINNET = 0x73b05F0D61F8d28520CD128471CB1ac3d89C4e17;
    address internal constant IMPL_MASTERCHEF_MAINNET = 0x464731fa072b1EF96C59CAC6449A076643E28d33;
    address internal constant IMPL_MLUM_STAKING_MAINNET = 0x8bEC63533BE85fb17AC781E71ACD281254ECd231;
    address internal constant IMPL_VOTER_MAINNET = 0x5f33eab35973CeDBF7C4fD12279a37bedB13C316;
    address internal constant IMPL_BRIBE_REWARDER_MAINNET = address(0);

    address internal constant WNATIVE_MAINNET = 0x6e47f8d48a01b44DF3fFF35d258A10A3AEdC114c;

    address internal constant TREASURY_MAINNET = 0xFc9a5c446F7C3Db0d94E29caFA1Ef13C91D1F56F;

    address internal constant ROUTER_V1_MAINNET = 0x531777F8c35fDe8DA9baB6cC7093A7D14a99D73E;
    address internal constant FARMZAPPER_MAINNET = 0xc9ED15fac26e34D04e14764fD0f5c88204c7FD63;

    address internal constant LB_HOOKS_MANAGER = 0x370e2EfdF6e14eae9C4CdEfCe59BEE460672cD67;
    address internal constant LB_HOOKS_LENS = 0xf54c810632F3F4Bcdc0bb408C12943e75A7DbdcC;
}
