// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract Faucet {
    uint256 public store;
    string[] public strList;

    address[] public participants;
    mapping(address => bool) public inParticipants;

    struct Node {
        uint[] history;
    }

    mapping(address => mapping(string => Node)) private direct_neighbors;

    function rateNeighbor(string memory target_ip, uint opinion) external returns (bool) {
        require(opinion <= 100, "Opinion should be less than or equal to 100");
        require(opinion >= 0, "Opinion should be greater than or equal to 0");

        if (!inParticipants[msg.sender]) {
            participants.push(msg.sender);
            inParticipants[msg.sender] = true;
        }

        Node storage neighbor = direct_neighbors[msg.sender][target_ip];
        neighbor.history.push(opinion);
        return true;
    }

    function getReputation(string memory target_ip) external view returns (uint) {
        int MULTIPLIER = 1000000;

        int[] memory opinions = new int[](participants.length);

        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint[] memory participant_history = direct_neighbors[participant][target_ip].history;
            uint participant_history_length = participant_history.length;

            if (participant == msg.sender || participant_history_length == 0) {
                continue;
            }

            int sum;
            for (int j = int(participant_history_length) - 1; j >= 0 && j >= int(participant_history_length) - 3; j--) {
                sum += int(participant_history[uint(j)]) * MULTIPLIER;
            }

            uint[] memory callee_opinion = direct_neighbors[msg.sender][target_ip].history;
            int trust_factor = 100;

            if (callee_opinion.length > 0) {
                trust_factor = int(callee_opinion[callee_opinion.length - 1]);
            }

            trust_factor *= MULTIPLIER;

            opinions[i] = sum / 3 * trust_factor / MULTIPLIER / MULTIPLIER;
        }

        int n_opinions;
        int sum_opinions;
        for (uint i = 0; i < participants.length; i++) {
            int opinion = opinions[i];
            if (opinion > 0) {
                sum_opinions += opinion * MULTIPLIER;
                n_opinions++;
            }
        }

        uint final_opinion;
        if (n_opinions != 0 && sum_opinions != 0) {
            final_opinion = uint(sum_opinions / n_opinions / MULTIPLIER);
        } else {
            final_opinion = 50;
        }

        return final_opinion;
    }

    function getLastBasicReputation(string memory target_ip) external view returns (uint[] memory) {
        uint[] memory opinions = new uint[](participants.length);

        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint[] memory participant_history = direct_neighbors[participant][target_ip].history;
            uint participant_history_length = participant_history.length;

            if (participant_history_length == 0) {
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
