// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract Faucet {
    address[] public participants;
    mapping(address => bool) public inParticipants;

    mapping(address => mapping(string => bool)) public neighbor_of;
    mapping(address => string) public address_ip;
    mapping(string => address) public ip_address;
    mapping(address => mapping(string => Node)) private address_ip_node;

    struct Node {
        uint256[] history;
    }

    function rateNeighbor(string memory to_ip, uint256 opinion)
        external
        returns (bool)
    {
        opinion = opinion < 0 ? 0 : opinion;
        opinion = opinion > 100 ? 100 : opinion;
        // require(opinion <= 100, "Opinion should be less than or equal to 100");
        // require(opinion >= 0, "Opinion should be greater than or equal to 0");
        require(
            valid_neighbors(msg.sender, to_ip),
            "The nodes are not confirmed neighbors"
        );

        Node storage neighbor = address_ip_node[msg.sender][to_ip];
        neighbor.history.push(opinion);
        return true;
    }

    function getReputation(string memory to_ip)
        external
        view
        returns (uint256)
    {
        int256 MULTIPLIER = 1000000;

        require(
            valid_neighbors(msg.sender, to_ip),
            "The nodes are not confirmed neighbors"
        );

        int256[] memory opinions = new int256[](participants.length);

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint256[] memory participant_history = address_ip_node[participant][
                to_ip
            ].history;
            uint256 participant_history_length = participant_history.length;

            if (participant_history_length == 0) {
                continue;
            }

            int256 sum;
            for (
                int256 j = int256(participant_history_length) - 1;
                j >= 0 && j >= int256(participant_history_length) - 3;
                j--
            ) {
                sum += int256(participant_history[uint256(j)]);
            }
            sum *= MULTIPLIER;

            opinions[i] = sum / int256(participant_history_length);
        }

        int256 n_opinions;
        int256 sum_opinions;
        for (uint256 i = 0; i < participants.length; i++) {
            int256 opinion = opinions[i];
            if (opinion > 0) {
                sum_opinions += opinion;
                n_opinions++;
            }
        }

        uint256 final_opinion;
        if (n_opinions != 0 && sum_opinions != 0) {
            final_opinion = uint256(sum_opinions / n_opinions / MULTIPLIER);
        } else {
            final_opinion = 25;
        }

        return final_opinion;
    }

    function register_neighbors(
        string[] memory neighbors,
        string memory socket_address
    ) external returns (bool) {
        address from_address = msg.sender;

        require(
            !inParticipants[from_address],
            "Sender already registered neighbors."
        );

        // register msg.sender as participant in federation
        participants.push(from_address);
        inParticipants[from_address] = true;

        // register msg.sender as neighbor of himself
        neighbor_of[from_address][socket_address] = true;

        // register all real neighbors
        address_ip[from_address] = socket_address;
        ip_address[socket_address] = from_address;
        for (uint256 i = 0; i < neighbors.length; i++) {
            neighbor_of[from_address][neighbors[i]] = true;
        }

        return true;
    }

    function valid_neighbors(address from_address, string memory to_ip)
        public
        view
        returns (bool)
    {
        string memory from_ip = address_ip[from_address];
        address to_address = ip_address[to_ip];
        return neighbor_of[from_address][to_ip] && neighbor_of[to_address][from_ip];
    }

    function valid_neighbors_debug(string memory from_ip, string memory to_ip)
        public
        view
        returns (bool)
    {
        address from_address = ip_address[from_ip];
        address to_address = ip_address[to_ip];
        return neighbor_of[from_address][to_ip] && neighbor_of[to_address][from_ip];
    }

    function neighbor_debug(address from_address, string memory to_ip) external view returns (bool){
        return neighbor_of[from_address][to_ip];
    }

    constructor() payable {}

}
