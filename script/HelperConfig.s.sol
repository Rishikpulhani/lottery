// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        uint256 entrancefee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callBackGasLimit;
        address link;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            entrancefee: 0.01 ether,
            interval: 30,
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0,
            callBackGasLimit: 500000,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            deployerKey: vm.envUint("PRIVATE_KEY") //THIS IS A CHEAT CODE TO GET THE PRIVATE KEY FROM THE ENVIRONMENT VARIBLES .env file
        });
    }

    uint256 public constant DEFAULT_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; //uint256 automatically will convert the hex to normal interger

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        //in this case we already have a mock contract give
        uint96 basefee = 0.25 ether; //this is actually paid in link tokens but here we use ether
        uint96 gasPriceLink = 0.0000000001 ether; //INSUFFICIENT BALANCE ERROR WAS AS HERE 1E9 ETHER WAS WRITTEN THIS DOES NOT MEAN DECIMAL, THIS IS 10 TO THE POWER 9 NOT -9
        vm.startBroadcast();
        VRFCoordinatorV2Mock vrfCoordinatormock = new VRFCoordinatorV2Mock(basefee, gasPriceLink);
        LinkToken link = new LinkToken();
        vm.stopBroadcast();
        return NetworkConfig({
            entrancefee: 0.01 ether,
            interval: 30,
            vrfCoordinator: address(vrfCoordinatormock),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 0, //out script will add this
            callBackGasLimit: 500000, //500000 gas
            link: address(link),
            deployerKey: DEFAULT_PRIVATE_KEY
        });
        //when on a actual test net we have to ensure that the private key being used to sign the txn of adding te consumer to our subscription is our own private key of that network
        //on the local machine we use a default anvil private key
    }
}
