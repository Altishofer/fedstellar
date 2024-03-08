// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract Faucet {
    uint256 public store;
    string[] public strList;


    address[] public participants;
    // msg.sender => registered
    mapping(address => bool) public inParticipants;

    // msg.sender => (ip => history[)
    struct Node {
        uint[] history;
    }

    mapping(address => mapping(string => Node)) private direct_neighbors;

    function rateNeighbor(string memory target_ip, uint opinion) external returns (bool){

        if (!inParticipants[msg.sender]){
            participants.push(msg.sender);
            inParticipants[msg.sender] = true;
        }

        Node storage neighbor = direct_neighbors[msg.sender][target_ip];

        if (100 < opinion || opinion < 0){
            opinion = 50;
        }

        neighbor.history.push(opinion);
        return true;
    }

    function getReputation(string memory target_ip) external view returns (uint){

        uint[] memory opinions = new uint[](participants.length);

        for (uint i; i<participants.length; i++){

            address participant = participants[i];

            uint[] memory participant_history = direct_neighbors[participant][target_ip].history;
            uint participant_history_length = participant_history.length;

            if (participant == msg.sender || participant_history_length == 0){
                continue;
            }

            uint sum;
            for (
                int j = int(participant_history_length) - 1;
                j >= 0 && j >= int(participant_history_length) - 3;
                j--
            ) {
                sum += participant_history[uint(j)];
            }

            uint[] memory callee_opinion = direct_neighbors[msg.sender][target_ip].history;
            uint trust_factor = 50;

            if (callee_opinion.length > 0){
                trust_factor = callee_opinion[callee_opinion.length - 1];
            }

            opinions[i] = sum / 3 * trust_factor;
        }

        uint n_opinions;
        uint sum_opinions;
        for (uint i; i < participants.length; i++){
            uint opinion = opinions[i];
            if (opinion > 0){
                sum_opinions += opinion;
                n_opinions++;
            }
        }

        uint final_opinion;
        if (n_opinions != 0){
            final_opinion = sum_opinions / n_opinions;
        } else {
            final_opinion = 50;
        }

        return final_opinion;
    }

    function getLastBasicReputation(string memory target_ip) external view returns (uint[] memory){

        uint[] memory opinions = new uint[](participants.length);

        for (uint i; i<participants.length; i++){

            address participant = participants[i];

            uint[] memory participant_history = direct_neighbors[participant][target_ip].history;
            uint participant_history_length = participant_history.length;

            if (participant == msg.sender || participant_history_length == 0){
                continue;
            }

            opinions[i] = participant_history[participant_history_length - 1];
        }

        return opinions;
    }


    constructor() payable {
        store = 99;
    }

    function writeStore(uint256 toStore) public {
        store = toStore;
    }

    function getStore() public view returns (uint256) {
        return store;
    }

    function getConstant() public pure returns (uint256) {
        return 55;
    }

    function addStr(string memory str) public {
        strList.push(str);
    }

    function getStrLst() public view returns (string[] memory){
        return strList;
    }
}
