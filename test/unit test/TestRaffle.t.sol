// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract TestRaffle is Test {
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    Raffle raffle;
    HelperConfig helperconfig;
    uint256 entrancefee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callBackGasLimit;
    address link;
    uint256 deployerKey;
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperconfig) = deployer.run();
        (entrancefee, interval, vrfCoordinator, gasLane, subscriptionId, callBackGasLimit, link, deployerKey) =
            helperconfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitialisesInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsIfYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        //to specify with which error
        raffle.enterRaffle();
    }

    function testRaffleAddPlayerWhenTheyEnter() external {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entrancefee}();
        address playerRecorded = raffle.getPlayerFromIndex(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() external {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entrancefee}();
    }

    function testCantEnterWhenRaffleIsCalculating() external {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entrancefee}();
        console.log("this is ", block.timestamp + interval + 1);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); //not actually needed but for safety
        console.log("this is 2 he", block.timestamp + interval + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entrancefee}();
    }

    function testCheckUpkeepReturnsFalseIfThereIsNoBalance() external {
        vm.warp(block.timestamp + interval + 1);
        (bool upkeep,) = raffle.checkUpKeep("");
        assert(upkeep == false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen() external RaffleEnterAndTimePassed {
        //to check this we can use the preform upkeep as for it the 1st 3 conditions are satissfied
        raffle.performUpkeep("");
        (bool upkeep,) = raffle.checkUpKeep("");
        assert(upkeep == false);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() external {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entrancefee}();
        vm.warp(block.timestamp + interval - 1);
        (bool upkeep,) = raffle.checkUpKeep("");
        assert(upkeep == false);
    }

    function testCheckUpkeepReturnsTrueIfParametersAreGood() external RaffleEnterAndTimePassed {
        (bool upkeep,) = raffle.checkUpKeep("");
        assert(upkeep == true);
    }

    function testPreformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() external RaffleEnterAndTimePassed {
        raffle.performUpkeep(""); //no way to test for no revert so if this runs normally then we can say the test has passed
    }

    function testPreformUpkeepRevertsIfCheckUpkeepIsFalse() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                address(raffle).balance,
                raffle.getNumberOfPlayers(),
                uint256(raffle.getRaffleState())
            )
        );
        //syntax for expect revert with custom error with parameters
        raffle.performUpkeep("");
    }

    modifier RaffleEnterAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entrancefee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }
    //we can also test the output of the events
    //event testing is required as the chainlink nodes listen to the evennts to know that they now have  to generate a random number

    function testPreformUpkeepUpdatesRaffleStateAndEmitsRequestId() external RaffleEnterAndTimePassed {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entrancefee}();
        vm.warp(block.timestamp + interval + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); //this Vm is different
        //this is a special type for foundry
        //here we already know that it is the 2nd event comming from preform upkeep as the 1st is from vrf coordinator contract
        //all logs ar recorded as bytes32 in foundry
        bytes32 requestId = entries[1].topics[1]; //topics referes to the internal array of indexed parameters
        //the 0th topi refers to the entire event
        assert(uint256(requestId) > 0); //as requestid would be 0 if not generated
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);
    }

    //if want to skip a test for some reason use this modifier
    modifier skipfork() {
        if (block.chainid == 11155111) {
            return;
        }
        _;
        //we will have to use this on those tests where we are using the mock contract
    }

    function testFullfilRandomWordsCanOnlyBeCalledAfterPrefromUpkeep(uint256 randomRequestId)
        external
        RaffleEnterAndTimePassed
        skipfork
    {
        vm.expectRevert("nonexistent request");
        ///the error message matters as it is returned by the computer it is not made up
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
        //here as the preform upkeep was ot called so no request id is generated
        //we want this to fail always
        //here this function can pnly be called by the vrf coorinator , here for testing purposes we are behaving as one and calling this function whereas on the actuall chain this wont work as we dont have the authority to call this function
    }

    function testFulfillRandomWordsPicksAwinnerResetsAndSendsMoney() external RaffleEnterAndTimePassed skipfork {
        //can be called by the chainlink node only but here we pretend to be one
        uint256 additionalEntries = 5;
        uint256 startingIndex = 1; //as one person has already entered through the modifier
        for (uint256 i = startingIndex; i < startingIndex + additionalEntries; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_BALANCE);
            raffle.enterRaffle{value: entrancefee}();
        }
        //now we pretend to be the chainlink node and call the fillfilrandomword function of the vrf coordinator contract
        //althhough this call can only be madde by the chainlink node so if this was on a actual testnet the we woundlnt have been able to act as the chainlink node and make this call
        //but since we are on a local anvil chain through our mock vrf coordinator , it is made in such a way that it acts as the chainlink vrf coordinator but here it allows someone to acts as the chainlink node and make the function call
        //this is done so that we can test the fulfill randomwords function of our raffle contract
        uint256 prise = entrancefee * (additionalEntries + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        console.log(uint256(requestId));
        console.log(address(raffle));
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getNumberOfPlayers() == 0);
        assert(address(raffle).balance == 0);
        assert(raffle.getLastTimeStamp() == block.timestamp);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(raffle.getRecentWinner() != address(0));
        //bytes32 winner = entries[2].topics[1];
        //assert(address(uint160(winner)) == raffle.getRecentWinner());
        assert((raffle.getRecentWinner()).balance == STARTING_BALANCE + prise - entrancefee);
    }
}
