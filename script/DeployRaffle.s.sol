// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        HelperConfig helperconfig = new HelperConfig();
        (
            uint256 entrancefee,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callBackGasLimit,
            address link,
            uint256 deployerKey
        ) = helperconfig.activeNetworkConfig();
        //here we are deconstructing the struct
        if (subscriptionId == 0) {
            //create subscription
            CreateSubscription createsubscription = new CreateSubscription();
            subscriptionId = createsubscription.createSubscription(vrfCoordinator, deployerKey);
            //fund it
            FundSubscription fundsubscription = new FundSubscription();
            fundsubscription.fundSubscription(vrfCoordinator, subscriptionId, link, deployerKey);
            //not doing through run() as we already have all the required stuff
            //add consumer to it
        }
        vm.startBroadcast();
        //a lot of things are chain dependant so we need a helper config
        Raffle raffle = new Raffle(entrancefee, interval, vrfCoordinator, gasLane, subscriptionId, callBackGasLimit);
        vm.stopBroadcast();
        AddConsumer addconsumer = new AddConsumer();
        addconsumer.addConsumer(vrfCoordinator, subscriptionId, address(raffle), deployerKey);
        return (raffle, helperconfig);
    }
}
