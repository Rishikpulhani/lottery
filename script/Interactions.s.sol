// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function CreateSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperconfig = new HelperConfig();
        (,, address vrfcoordinator,,,,, uint256 deployerKey) = helperconfig.activeNetworkConfig();
        return createSubscription(vrfcoordinator, deployerKey);
    }
    //we are creating different functions to ensure modularity

    function createSubscription(address vrfcoordinator, uint256 deployerKey) public returns (uint64) {
        console.log(block.chainid);
        vm.startBroadcast(deployerKey);
        //this will actually send our address to the 2vrf coordinator contract, so it will create the subscription for our account, then we will have to add the raffle contract to our subscription
        //the msg.sender to the vrf coordinator is set to our address not the raffle or the deploy script or test contract address, this is due to the functionality of the vm cheatcode
        uint64 subid = VRFCoordinatorV2Mock(vrfcoordinator).createSubscription();
        vm.stopBroadcast();
        console.log(subid);
        return subid;
    }

    function run() public returns (uint64) {
        //subscription id is returned here which is a uint64
        return CreateSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 constant FUND_AMOUNT = 30 ether;

    function fundSubscriptionThroughConfig() public {
        HelperConfig helperconfig = new HelperConfig();
        //not did inn vm.startBroadcast(); as we dont want to actually create this on chain, we just need its help here to fetch sime data in that contract
        (,, address vrfcoordinator,, uint64 subId,, address link, uint256 deployerKey) =
            helperconfig.activeNetworkConfig();
        fundSubscription(vrfcoordinator, subId, link, deployerKey);
    }
    //here we have to ensure that all creation funding and consumer addition are occuring from the same deployer key

    function fundSubscription(address vrfcoordinator, uint64 subId, address link, uint256 deployerKey) public {
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfcoordinator).fundSubscription(subId, FUND_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(vrfcoordinator, FUND_AMOUNT, abi.encode(subId));
            vm.stopBroadcast();
        }
    }

    function run() public {
        fundSubscriptionThroughConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperconfig = new HelperConfig();
        (,, address vrfcoordinator,, uint64 subId,,, uint256 deployerKey) = helperconfig.activeNetworkConfig();
        addConsumer(vrfcoordinator, subId, raffle, deployerKey);
    }

    function addConsumer(address vrfcoordinator, uint64 subId, address raffle, uint256 deployerKey) public {
        vm.startBroadcast(deployerKey); //we can just pass in the private key in the broadcast
        VRFCoordinatorV2Mock(vrfcoordinator).addConsumer(subId, raffle);
        vm.stopBroadcast();
    }

    function run() public {
        address raffle = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(raffle);
    }
}
