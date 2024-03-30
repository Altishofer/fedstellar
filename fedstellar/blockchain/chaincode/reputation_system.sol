// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract ReputationSystem {

    constructor() payable {}

    struct Edge {
        bool neighbor;
        uint256[] opinions;
    }

    struct Node {
        string name;
        address account;
        uint centrality;
        uint index;
        bool registered;
        bool existing;
    }

    // scale all values up to reduce error due to missing floats in solidity
    uint256 MULTIPLIER = 1000000;

    // participating nodes of FL scenario
    Node[] public nodes;

    // allow fast access of Nodes
    mapping(address => Node) public accounts;
    mapping(string => Node) public names;

    // adjacency matrix of reputation system
    // ordered by index of participants list
    Edge[][] public adj_matrix;

    function register_neighbors(string[] memory neighbors, string memory name ) external returns (bool) {

        // ensure that nodes cannot change their neighborhood
        require(accounts[msg.sender].registered == false, "Node already declared their neighbors");

        // check if participant was registered as neighbor before
        Node storage node = names[name];

        // check if node was already created as neighbor
        if (node.existing){

            // if node was partially registered as neighbor
            // complete seting up node's information
            node.account = msg.sender;
            node.registered = true;
            accounts[msg.sender] = node;

        } else {

            // if node is not not known to the contract, set up completely
            node.name = name;
            node.account = msg.sender;
            node.index = nodes.length;
            node.registered = true;
            node.existing = true;

            // add node to hash tables
            accounts[msg.sender] = node;
            names[name] = node;

            // push node to list of participants
            nodes.push(node);
        }

        // check if neighbors were registered for the adj_matrix before
        for (uint i=0; i<neighbors.length; i++){

            string memory neighbor_name = neighbors[i];

            // check if neighbor was registered by any other node before
            if (names[neighbor_name].existing == false){

                // partially setup neighbor as participant
                Node storage neighbor = names[neighbor_name];
                neighbor.name = neighbor_name;
                neighbor.index = nodes.length;
                neighbor.existing = true;

                // add neighbor to hash table
                names[neighbor_name] = neighbor;

                // push neighbor to list of participants
                nodes.push(neighbor);
            }
        }

        // increase the x dimension of the existing adj_matrix's rows
        for (uint256 y=0; y<adj_matrix.length; y++){

            for (uint256 x=0; x<nodes.length - adj_matrix.length; x++){

                adj_matrix[y].push(Edge(false, new uint256[](0)));
            }
        }

        // increase the y dimension of the existing adj_matrix's columns
        for (uint256 y=0; y<nodes.length - adj_matrix.length; y++){

            adj_matrix.push();

            for (uint256 x=0; x<nodes.length; x++){

                adj_matrix[adj_matrix.length -1].push(Edge(false, new uint256[](0)));
            }
        }

        // register all neighbors for msg.sender
        for (uint j=0; j<neighbors.length; j++){

            // get column index of neighbor
            uint256 neighbor_index = names[neighbors[j]].index;

            // set Edge to neighbor of calling node
            adj_matrix[node.index][neighbor_index].neighbor = true;
        }

        betweenness_centrality();

        return true;
    }

    function rateNeighbor(string memory neighbor_name, uint256 opinion) external returns (bool) {
        require(opinion <= 100, "Opinion should be less than or equal to 100");
        require(opinion >= 0, "Opinion should be greater than or equal to 0");

        // get adj_matrix indexes of registered participants
        require(accounts[msg.sender].registered, "msg.sender did not register the neighborhood.");
        require(names[neighbor_name].registered, "target node did not register their neighborhood.");

        uint index_sender = accounts[msg.sender].index;
        uint index_target = names[neighbor_name].index;

        // check if nodes did both confirm their neighborhood
        require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors");

        // push opinion value to Edge object in adj_matrix
        Edge storage edge = adj_matrix[index_sender][index_target];

        //edge.opinions.push(opinion);
        edge.opinions.push(opinion);

        return true;
    }

    function valid_neighbors(uint node_a, uint node_b) public view returns (bool){
        return (adj_matrix[node_a][node_b].neighbor && adj_matrix[node_b][node_a].neighbor) || node_a == node_b;
    }


    function getReputation(string memory name_target) external view returns (uint256){

        // get adj_matrix indexes of registered participants
        require(accounts[msg.sender].registered, "msg.sender did not register the neighborhood.");
        require(names[name_target].registered, "target node did not register their neighborhood.");

        // get adj_matrix indexes of registered participants
        uint256 index_sender = accounts[msg.sender].index;
        uint256 index_target = names[name_target].index;

        // check if nodes did both confirm their neighborhood
        require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors");

        uint256[] memory opinions = new uint256[](nodes.length);

        for (uint256 i = 0; i < nodes.length; i++) {
            uint256[] memory participant_history = adj_matrix[i][uint(index_target)].opinions;
            uint256 hist_len = participant_history.length;

            if (hist_len == 0) {continue;}

            uint256 sum;
            uint256 hist_included;
            for (
                uint256 j = uint256(hist_len) - 1;
                j >= 0 && j >= uint256(hist_len) - 3;
                j--
            ) {
                hist_included++;
                sum += uint256(participant_history[uint256(j)]);
            }
            sum *= MULTIPLIER;

            opinions[i] = sum / uint256(hist_included);
        }

        uint256 n_opinions;
        uint256 sum_opinions;
        for (uint256 i = 0; i < nodes.length; i++) {
            uint256 opinion = opinions[i];
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


    function betweenness_centrality() public returns (bool){
        // This algorithm computes BFS for each node
        // This function calculates the betweenness centrality for each node in a graph
        // Betweenness centrality measures how often a node lies on the shortest path between other nodes

        uint256[] memory centrality = new uint256[](nodes.length);

        // setup stack for BFS
        uint256[] memory stack = new uint256[](nodes.length);
        uint256 stack_length;

        // loop over all nodes in adjacency matrix
        for (uint256 y=0; y<nodes.length; y++){

            for (uint256 x=y+1; x<nodes.length; x++){

                // skip  nodes without an edge between them
                if (adj_matrix[y][x].neighbor == false){
                    continue;
                }

                // initialize array for recording nodes included in shortest path
                uint256[] memory shortest_paths = new uint256[](nodes.length);
                shortest_paths[y] = 1;

                // push starting node to stack
                stack[stack_length] = y;
                stack_length++;

                // Perform BFS to find shortest paths
                while (stack_length > 0){

                    uint256 y_node = stack[stack.length -1];
                    stack_length--;

                    for (uint256 x_neighbor=0; x_neighbor<nodes.length; x_neighbor++){

                        // skip non-neighboring nodes
                        if (adj_matrix[y_node][x_neighbor].neighbor == false){
                            continue;
                        }

                        // If the neighbor has not been visited yet, update its shortest path count
                        if (shortest_paths[x_neighbor] == 0){

                            stack[stack_length] = x_neighbor;
                            stack_length++;

                            shortest_paths[x_neighbor] = shortest_paths[y_node];

                        } else if (shortest_paths[x_neighbor] == shortest_paths[y_node]) {
                            // If the neighbor has the same shortest path count as the current node,
                            // add its count to the current node's count
                            shortest_paths[x_neighbor] += shortest_paths[y_node];
                        }

                    }
                }

                // Update centrality values for all nodes except the starting node
                for (uint i=0; i<nodes.length; i++){
                    if (i != y && i != x){
                        centrality[i] += shortest_paths[i];
                    }
                }
            }
        }

        // Calculate the total number of possible paths
        uint total_paths = (MULTIPLIER * (nodes.length -1) * (nodes.length -2)) / 2;

        // Normalize centrality values and assign them to the nodes
        for (uint256 n=0; n<nodes.length; n++){
            nodes[n].centrality = (MULTIPLIER * centrality[n]) / total_paths;
        }

        return true;
    }

    function getCentrality(string memory ip) public view returns (uint256){
        return names[ip].centrality;
    }
}