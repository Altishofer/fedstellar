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

    struct Dict {
        string key;
        uint256 value;
    }

    struct DebugDict {
        string key;
        uint256 reputation;
        uint256 stddev_count;
        uint final_reputation;
        uint avg;
        uint stddev;
    }

    // Events for debugging
    event Debug(string what, uint256 variable);
    event Debug(string what, uint256[] variable);
    event Debug(uint256 x, uint256 y, bool neighbors, uint position);
    event Debug(uint256 from, uint256 to, uint256 fromDist, uint256 toDist);

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
            names[name] = node;
            nodes[node.index] = node;

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

        // increase the y dimension of the existing adj_matrix's columns
        while (adj_matrix.length < nodes.length){
            adj_matrix.push();
        }

        // increase the x dimension of the existing adj_matrix's rows
        for (uint256 y=0; y<adj_matrix.length; y++){

            while (adj_matrix[y].length < nodes.length){
                adj_matrix[y].push(Edge(false, new uint256[](0)));
            }
        }

        // register all neighbors for msg.sender
        for (uint j=0; j<neighbors.length; j++){

            // get column index of neighbor
            uint256 neighbor_index = names[neighbors[j]].index;

            // set Edge to neighbor of calling node
            adj_matrix[node.index][neighbor_index].neighbor = true;
        }

        // update centrality values for all nodes
        return betweenness_centrality();
    }

    function get_adj() public view returns (bool[] memory){
        bool[] memory r = new bool[](nodes.length * nodes.length);
        uint256 idx;
        for (uint y=0; y<nodes.length; y++){
            for (uint x=0; x<nodes.length; x++){
                r[idx] = adj_matrix[y][x].neighbor;
                idx++;
            }
        }
        return r;
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

    function rate_neighbors(Dict[] memory neighbors) public returns (bool){

        require(accounts[msg.sender].registered, "msg.sender did not register the neighborhood.");

        for (uint i=0; i<neighbors.length; i++){

            Dict memory neighbor = neighbors[i];

            if (names[neighbor.key].registered == false){
                continue;
            }

            require(neighbor.value <= 100, "Opinion should be less than or equal to 100");
            require(neighbor.value >= 0, "Opinion should be greater than or equal to 0");

            // get adj_matrix indexes of registered participants
            require(names[neighbor.key].registered, "target node did not register their neighborhood.");

            uint index_sender = accounts[msg.sender].index;
            uint index_target = names[neighbor.key].index;

            // check if nodes did both confirm their neighborhood
            require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors");

            // push opinion value to Edge object in adj_matrix
            Edge storage edge = adj_matrix[index_sender][index_target];

            //edge.opinions.push(opinion);
            edge.opinions.push(neighbor.value);
        }

        return true;
    }

    function confirm_registration() public view returns(bool){
        return accounts[msg.sender].registered;
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
            uint256[] memory participant_history = adj_matrix[i][index_target].opinions;
            uint256 hist_len = participant_history.length;

            if (hist_len == 0) {continue;}

            uint256 sum;
            uint256 hist_included;
            for (
                int256 j = int256(hist_len) - 1;
                j >= 0 && j >= int256(hist_len) - 3;
                j--
            ) {
                hist_included++;
                sum += participant_history[uint256(j)];
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

    function get_reputations(string[] memory neighbors) public view returns (Dict[] memory){

        Dict[] memory reputations = new Dict[](nodes.length);

        for (uint j=0; j<neighbors.length; j++){

            string memory name_target = neighbors[j];

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
                uint256[] memory participant_history = adj_matrix[i][index_target].opinions;
                uint256 hist_len = participant_history.length;

                if (hist_len == 0) {continue;}

                uint256 sum;
                uint256 hist_included;
                for (
                    int256 x = int256(hist_len) - 1;
                    x >= 0 && x >= int256(hist_len) - 3;
                    x--
                ) {
                    hist_included++;
                    sum += participant_history[uint256(x)];
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

            reputations[j] = Dict(name_target, final_opinion);
        }

        return reputations;
    }

    function abs(int x) private pure returns (uint) {
        x = x >= 0 ? x : -x;
        return uint(x);
    }

    function sqrt(uint x) public pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function betweenness_centrality() public returns (bool){
        uint256[] memory centrality = new uint256[](nodes.length);

        // Loop over all nodes in adjacency matrix
        for (uint256 y = 0; y < nodes.length; y++) {
            // Initialize array for recording nodes included in shortest path
            uint256[] memory shortest_paths = new uint256[](nodes.length);

            // keep record of all parent node in the shortest paths
            uint256[][] memory parent =  new uint256[][](nodes.length);

            // Setup queue for BFS
            uint256[] memory queue = new uint256[](nodes.length);
            uint256 queue_start = 0;
            uint256 queue_end = 0;

            // Perform BFS for each node
            for (uint256 i = 0; i < nodes.length; i++) {
                shortest_paths[i] = 0;
                parent[i] = new uint256[](nodes.length);
                for (uint j=0; j <nodes.length; j++){
                    parent[i][j] = 0;
                }
            }

            // Push starting node to queue
            queue[queue_start] = y;
            queue_end++;

            // assign path length to node itself to 1
            shortest_paths[y] = 1;

            // Perform BFS to find shortest paths
            while (queue_end - queue_start > 0) {
                uint256 y_node = queue[queue_start];
                queue_start++;

                for (uint256 x_neighbor = 0; x_neighbor < nodes.length; x_neighbor++) {
                    // Skip non-neighboring nodes
                    if (adj_matrix[y_node][x_neighbor].neighbor == false || adj_matrix[x_neighbor][y_node].neighbor == false) {
                        continue;
                    }

                    // If the neighbor has not been visited yet, push it to the queue
                    if (shortest_paths[x_neighbor] == 0) {
                        queue[queue_end] = x_neighbor;
                        queue_end++;

                        // Update shortest path count for the neighbor
                        shortest_paths[x_neighbor] += shortest_paths[y_node] +1;
                    }

                    if (shortest_paths[x_neighbor] == shortest_paths[y_node] +1){
                        // record y_node as possible neighbor for x_neighbor if on the shortest path
                        parent[x_neighbor][y_node] = 1;
                    }
                }
            }

            // simulate a max heap for iterating trough tree, starting at leaf nodes
            uint[] memory n_paths = new uint[](nodes.length);
            for (uint j=0; j<nodes.length; j++){
                uint idx;
                for (uint i=0; i<nodes.length; i++){
                    if (shortest_paths[i] > shortest_paths[idx]){
                        idx = i;
                    }
                }

                // if max value is zero, all nodes were visited
                if (shortest_paths[idx] == 0){
                    continue;
                }

                // add number of shortest paths to all parent nodes
                // to which the current node leads to
                for (uint i=0; i<nodes.length; i++){
                    if (parent[idx][i] == 1){
                        n_paths[i] += n_paths[idx] +1;
                    }
                }

                // remove visited node from max heap
                shortest_paths[idx] = 0;
            }

            // Update centrality values for all nodes except the starting node
            for (uint256 i = 0; i < nodes.length; i++) {
                if (i != y) {
                    centrality[i] += n_paths[i];
                }
            }
        }

        // Calculate the total number of shortest paths
        uint256 total_paths;
        for (uint256 t = 0; t < centrality.length; t++) {
            total_paths += centrality[t];
        }

        // Normalize centrality values and assign them to the nodes
        for (uint256 n = 0; n < nodes.length; n++) {
            if (total_paths > 0){
                nodes[n].centrality = (MULTIPLIER * centrality[n]) / total_paths;
            } else {
                nodes[n].centrality = uint256(0);
            }
        }

        return true;
    }

    function get_centrality() public view returns (uint[] memory){
        uint256[] memory ret = new uint256[](nodes.length);
        for (uint256 i=0; i<nodes.length; i++){
            ret[i] = nodes[i].centrality;
        }
        return ret;
    }

    function debug_get_reputations(uint256 node) public returns (DebugDict[] memory) {
        DebugDict[] memory reputations = new DebugDict[](nodes.length);
        string[] memory all_nodes = new string[](nodes.length);

        uint256 cnt;
        for (uint256 n = 0; n < nodes.length; n++) {
            if (valid_neighbors(nodes[node].index, nodes[n].index) == false) {
                continue;
            }
            all_nodes[cnt] = nodes[n].name;
            cnt++;
        }

        string[] memory neighbors = new string[](cnt);
        for (uint256 nei = 0; nei < cnt; nei++) {
            neighbors[nei] = all_nodes[nei];
        }

        for (uint256 j = 0; j < neighbors.length; j++) {
            string memory name_target = neighbors[j];

            uint256 index_sender = accounts[msg.sender].index;
            uint256 index_target = names[name_target].index;

            require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors");

            uint256[] memory opinions = new uint256[](nodes.length);

            for (uint256 i = 0; i < nodes.length; i++) {
                uint256[] memory participant_history = adj_matrix[i][index_target].opinions;
                uint256 hist_len = participant_history.length;

                if (hist_len == 0) {
                    continue;
                }

                uint256 sum;
                uint256 hist_included;
                for (int256 x = int256(hist_len) - 1; x >= 0 && x >= int256(hist_len) - 3; x--) {
                    hist_included++;
                    sum += participant_history[uint256(x)];
                }

                if (hist_included > 0) {
                    sum *= MULTIPLIER;
                    opinions[i] = sum / hist_included;
                }
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
                final_opinion = sum_opinions / n_opinions / MULTIPLIER;
            } else {
                final_opinion = 25;
            }

            reputations[j] = DebugDict(name_target, final_opinion, 0, 0, 0, 0);
        }

        uint256 sum_opinions_std = 0;

        for (uint256 i = 0; i < nodes.length; i++) {
            sum_opinions_std += reputations[i].reputation;
        }

        emit Debug("sum_opinions", sum_opinions_std);
        emit Debug("reputations.length", reputations.length);

        if (sum_opinions_std == 0 || reputations.length <= 1) {
            return reputations;
        }

        uint256 avg = sum_opinions_std / reputations.length;
        uint256 stddev = 0;

        emit Debug("avg", avg);


        for (uint256 i = 0; i < nodes.length; i++) {
            uint256 diff = reputations[i].reputation > avg ? reputations[i].reputation - avg : avg - reputations[i].reputation;
            stddev += diff * diff; // Squaring to calculate variance
        }

        stddev /= reputations.length;

        // Overflow check and correction
        if (stddev > type(uint256).max - 1) {
            stddev = type(uint256).max - 1;
        }

        // Avoid square root of 0 or very small numbers
        if (stddev > 0) {
            stddev = sqrt(stddev);
        }

        emit Debug("stddev", stddev);

        uint256 outlier = 2;
        for (uint256 i = 0; i < nodes.length; i++) {
            if (stddev <= 0 ){
                continue;
            }

            uint256 cntt = abs(int256(reputations[i].reputation) - int(avg)) / stddev;

            if (cntt > outlier) {
                reputations[i].final_reputation = cntt > 0 ? reputations[i].reputation : reputations[i].reputation / cntt;
                reputations[i].stddev_count = cntt;
                reputations[i].stddev = stddev;
                reputations[i].avg = avg;

                emit Debug("final_reputation", reputations[i].final_reputation);
                emit Debug("stddev_count", reputations[i].stddev_count);
                emit Debug("stddev", reputations[i].stddev);
                emit Debug("avg", reputations[i].avg);
                emit Debug("reputation", reputations[i].reputation);
            }
        }

        return reputations;
    }
}