// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract ReputationSystem {

    constructor() payable {}

    struct Edge {
        bool neighbor;
        uint256[] opinions;
    }

    // addresses and names of participants
    address[] public accounts;
    string[] public names;

    // allow fast access of index +1 of names and accounts
    mapping(address => uint256) public index_accounts;
    mapping(string => uint256) public index_names;

    // adjacency matrix of reputation system
    // ordered by index of participants list
    Edge[][] public adj_matrix;

    // temporary helper structure for simplified copy process
    Edge[] public tmp_array;

    function register_neighbors(string[] memory neighbors, string memory name ) external returns (bool) {
        require(index_accounts[msg.sender] == 0, "Node already declared their neighbors");

        // get index of last free position on participants list
        uint256 curr_length = names.length;

        // check if participant was registered as neighbor before
        uint256 sender_index = index_names[name];
        if (sender_index == 0){

            // register sender's account address as participant
            accounts.push(msg.sender);

            // register index +1 of participant
            // +1 since solidity initializes all elements to 0
            index_accounts[msg.sender] = curr_length +1;

            // register sender's name as participant
            names.push(name);

            // register index +1 of participant
            // +1 since solidity initializes all elements to 0
            index_names[name] = curr_length +1;

            // update the pointer to the senders coordinate in the adj_matrix
            sender_index = curr_length;
        } else {
            // update the pointer to the senders coordinate in the adj_matrix
            sender_index -= 1;

            // register sender's account address as participant
            // use index of already registered name
            accounts[sender_index] = msg.sender;

            // register index +1 of participant
            // +1 since solidity initializes all elements to 0
            index_names[name] = sender_index +1;
        }

        // check if neighbors were registered for the adj_matrix before
        for (uint i=0; i<neighbors.length; i++){
            string memory neighbor = neighbors[i];
            if (index_names[neighbor] == 0){
                // if not, register them as participants
                index_names[neighbor] = names.length +1;
                names.push(neighbor);
                accounts.push(address(0));
            }
        }

        // increase the x dimension of the existing adj_matrix
        for (uint256 y=0; y<adj_matrix.length; y++){
            for (uint256 x=0; x<names.length - adj_matrix.length; x++){
                adj_matrix[y].push(Edge(false, new uint256[](0)));
            }
        }

        // increase the y dimension of the existing adj_matrix
        for (uint256 y=0; y<names.length - adj_matrix.length; y++){
            adj_matrix.push();
            for (uint256 x=0; x<names.length; x++){
                adj_matrix[adj_matrix.length -1].push(Edge(false, new uint256[](0)));
            }
        }

        // register all neighbors for msg.sender
        for (uint j=0; j<neighbors.length; j++){
            uint256 neighbor_index = index_names[neighbors[j]] -1;
            adj_matrix[sender_index][neighbor_index].neighbor = true;
        }

        return true;
    }

    function rateNeighbor(string memory neighbor_name, uint256 opinion) external returns (bool) {
        require(opinion <= 100, "Opinion should be less than or equal to 100");
        require(opinion >= 0, "Opinion should be greater than or equal to 0");

        // get adj_matrix indexes of registered participants
        uint index_sender = index_accounts[msg.sender] -1;
        uint index_target = index_names[neighbor_name] -1;

        // check if nodes did both confirm their neighborhood
        require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors");

        // push opinion value to Edge object in adj_matrix
        Edge storage edge = adj_matrix[index_sender][index_target];
        //edge.opinions.push(opinion);
        edge.opinions.push(opinion);

        return true;
    }

    function valid_neighbors(uint node_a, uint node_b) public view returns (bool){
        return adj_matrix[node_a][node_b].neighbor && adj_matrix[node_b][node_a].neighbor || node_a == node_b;
    }


    function getReputation(string memory name_target) external view returns (uint256){

        // scale all values up to reduce error due to missing floats in solidity
        int256 MULTIPLIER = 1000000;

        // get adj_matrix indexes of registered participants
        int index_sender = int(index_accounts[msg.sender] -1);
        int index_target = int(index_names[name_target] -1);

        require(index_sender >= 0 && index_target >= 0, "Nodes are not yet registered.");

        // check if nodes did both confirm their neighborhood
        require(valid_neighbors(uint256(index_sender), uint256(index_target)), "Nodes are not confirmed neighbors");

        int256[] memory opinions = new int256[](names.length);

        for (uint256 i = 0; i < names.length; i++) {
            uint256[] memory participant_history = adj_matrix[i][uint(index_target)].opinions;
            uint256 hist_len = participant_history.length;

            if (hist_len == 0) {continue;}

            int256 sum;
            int256 hist_included;
            for (
                int256 j = int256(hist_len) - 1;
                j >= 0 && j >= int256(hist_len) - 3;
                j--
            ) {
                hist_included++;
                sum += int256(participant_history[uint256(j)]);
            }
            sum *= MULTIPLIER;

            opinions[i] = sum / int256(hist_included);
        }

        int256 n_opinions;
        int256 sum_opinions;
        for (uint256 i = 0; i < names.length; i++) {
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
}