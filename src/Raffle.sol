// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    //this is a consumer contract we are designing on our own with some neccessary functions
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address private s_recentWinner;
    address payable[] private s_players;
    RaffleState private s_RaffleState;
    uint256 private s_lastTimeStamp;

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entrancefee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        //interval is for the duration of the lottery in seconds
        i_entranceFee = entrancefee;
        i_interval = interval;
        i_gasLane = gasLane;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_callbackGasLimit = callBackGasLimit;
        i_subscriptionId = subscriptionId;
        s_RaffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_RaffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        //we also want that no one enters the lottery/raffle while we are in the process of drawing the winner so we need to define the state of the raffle so use enum if having just more that 2 states (if 2 states the use bool)

        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }
    //code to fetch that generated random number --> txn 2
    //this is the func the chainlink automation nodes will call to see if it is time to run the function//this function will return true only if
    //1. enough time has passed to pull the lottery
    //2. raffle is in open state
    //3. the contract has eth and players
    //4.the subscription is funded with link
    //the chainlink automation node will keep calling this function PERIODICALLY to check for the need of an upkeep or lottery pull

    function checkUpKeep(bytes memory /*checkdata*/ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /*preformdata*/ )
    {
        //this type of sytax for function parameters is used when we have to show that there is a parameter required by this function but it won't be used ahead in the function execution
        //this syntax for function returns parameter is when we dont want to initialise the variable inside the function
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = (s_RaffleState == RaffleState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    //we will use chainlink automation to progamatically call the PickWinner function when it is time to call it
    function performUpkeep(bytes calldata /*performdata*/ ) external {
        (bool upkeepNeeded,) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_RaffleState));
        }
        s_RaffleState = RaffleState.CALCULATING;
        //code to request for a random number --> txn 1
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane   //chain dependant so immuatble from constructor
            i_subscriptionId, //chain dependant so immuatble from constructor
            REQUEST_CONFIRMATIONS, //not chain dependant
            i_callbackGasLimit, //chain dependant as depend on chain traffic
            NUM_WORDS //not chain dependant
        );
        emit RequestedRaffleWinner(requestId); //this is actually redundant as the vrf coordinator contract aalso emits the request id
    }
    //Once the VRFCoordinator has received and validated the oracle's response
    // to your request, it will call your contract's fulfillRandomWords method.
    //this is from the vrfconsumerbase contract

    function fulfillRandomWords(
        uint256, /*requestId*/
        uint256[] memory randomWords //array of random numbers returned
    ) internal override {
        //this function in coordinator contract and is called by the chainlink node to get our random number back to us
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_RaffleState = RaffleState.OPEN;
        s_players = new address payable[](0); //if fill some other number then fill that many number of address(0) elements in th new array
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // getter functions
    function getEntranceFees() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_RaffleState;
    }

    function getPlayerFromIndex(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
