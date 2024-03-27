// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract Faucet {
    uint256 public store;
    string[] public strList;

    address[] public participants;
    mapping(address => bool) public inParticipants;

    mapping(address => mapping(string => bool)) neighbor_of;
    mapping(address => string) address_ip;
    mapping(string => address) ip_address;

    struct Node {
        uint[] history;
    }

    mapping(address => mapping(string => Node)) private direct_neighbors;

    function rateNeighbor(string memory to_ip, uint opinion) external returns (bool) {
        require(opinion <= 100, "Opinion should be less than or equal to 100");
        require(opinion >= 0, "Opinion should be greater than or equal to 0");
        require(valid_neighbors(msg.sender, to_ip), "The nodes are not confirmed neighbors");

        Node storage neighbor = direct_neighbors[msg.sender][to_ip];
        neighbor.history.push(opinion);
        return true;
    }

    function valid_neighbors(address from_address, string memory to_ip) private view returns (bool){
        string memory from_ip = address_ip[from_address];
        address to_address = ip_address[to_ip];
        if (neighbor_of[from_address][to_ip] && neighbor_of[to_address][from_ip]){
            return true;
        }
        return false;
    }

    function getReputation(string memory to_ip) external view returns (uint) {
        int MULTIPLIER = 1000000;

        require(valid_neighbors(msg.sender, to_ip), "The nodes are not confirmed neighbors");

        int[] memory opinions = new int[](participants.length);

        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint[] memory participant_history = direct_neighbors[participant][to_ip].history;
            uint participant_history_length = participant_history.length;

            if (participant_history_length == 0) {
                continue;
            }

            int sum;
            for (int j = int(participant_history_length) - 1; j >= 0 && j >= int(participant_history_length) - 3; j--) {
                sum += int(participant_history[uint(j)]);
            }
            sum *= MULTIPLIER;

            opinions[i] = sum / int(participant_history_length);
        }

        int n_opinions;
        int sum_opinions;
        for (uint i = 0; i < participants.length; i++) {
            int opinion = opinions[i];
            if (opinion > 0) {
                sum_opinions += opinion;
                n_opinions++;
            }
        }

        uint final_opinion;
        if (n_opinions != 0 && sum_opinions != 0) {
            final_opinion = uint(sum_opinions / n_opinions / MULTIPLIER);
        } else {
            final_opinion = 25;
        }

        return final_opinion;
    }

    function getLastBasicReputation(string memory to_ip) external view returns (uint[] memory) {
        uint[] memory opinions = new uint[](participants.length);

        for (uint i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint[] memory participant_history = direct_neighbors[participant][to_ip].history;
            uint participant_history_length = participant_history.length;

            if (participant_history_length == 0) {
                continue;
            }

            opinions[i] = participant_history[participant_history_length - 1];
        }

        return opinions;
    }

    function register_neighbors(string[] memory neighbors, string memory socket_address) external returns (bool){
        address from_address = address(msg.sender);

        require(!inParticipants[from_address], "Sender already registered neighbors.");

        participants.push(from_address);
        inParticipants[from_address] = true;

        address_ip[from_address] = socket_address;
        ip_address[socket_address] = from_address;
        for (uint i=0; i<neighbors.length; i++){
            neighbor_of[from_address][neighbors[i]] = true;
        }

        return true;
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
