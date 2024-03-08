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
    mapping(address => mapping(string => Node)) public direct_neighbors;

    function rateNeighbor(string target_ip, uint opinion) external returns (bool){
        if (!inParticipants[msg.sender]){
            participants.push(msg.sender);
            inParticipants[msg.sender] = true;
        }
        Node memory neighbor = direct_neighbors[msg.sender][target_ip];
        neighbor.history.push(opinion);
        return true;
    }

    function getReputation(string target_ip) external returns (uint[][] memory){
        uint[][] memory opinions = new uint[];
        for (uint i; i<participants.length; i++){
            address participant = participants[i];
            if (direct_neighbors[participant][target_ip].history.length > 0){
                opinions.push(participant[target_ip].history);
            }
        }
        return opinions;
    }

    constructor() payable {
        store = 99;
        reputation[msg.sender].push(100);
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
