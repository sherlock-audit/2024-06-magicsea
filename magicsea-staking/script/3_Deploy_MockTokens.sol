// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ILum} from "../src/interfaces/ILum.sol";
import {IMasterChef} from "../src/interfaces/IMasterChef.sol";
import {ERC20Mock, IERC20} from "../src/mocks/ERC20Mock.sol";
import {LumMock}  from "../src/mocks/LumMock.sol";
import {Addresses} from "./config/Addresses.sol";

contract CoreDeployer is Script {
    function setUp() public {}

    address admin = 0xdeD212B8BAb662B98f49e757CbB409BB7808dc10;

    function run() public returns (ERC20Mock mlumMock) {
        address deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        vm.startBroadcast(deployer);
        mlumMock = new ERC20Mock("MagicLum Mock Token", "mockMLUM", deployer, deployer);

        mlumMock.mint(deployer, 10_000e18);
        vm.stopBroadcast();
    }
}


contract MintAndFundMasterChef is Script {
    uint256 pk;
    address deployer;
    
    function run() public {
        pk = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(pk);

        ILum lum = ILum(Addresses.LUM_TESTNET);

        bytes32 minterRole = keccak256("MINTER_ROLE");
        bool isAdminMinter = LumMock(address(lum)).hasRole(minterRole, deployer);
        console.log("is Admin Minter -->", isAdminMinter);

        if (!isAdminMinter) {
            console.log("Granting Minter Role to Admin");
            vm.broadcast(pk);
            LumMock(address(lum)).grantRole(minterRole, deployer);
        }

        // mint for 2 month
        IMasterChef masterChef = IMasterChef(Addresses.PROXY_MASTERCHEF_TESTNET);
        uint256 emission = masterChef.getLumPerSecond();

        // calc totalEmission for 2 month in seconds
        uint256 totalEmission = emission * 60 * 60 * 24 * 30 * 2;

        console.log("Total Emission -->", totalEmission);

        vm.broadcast(pk);
        lum.mint(Addresses.PROXY_MASTERCHEF_TESTNET, totalEmission);
    }

    
}