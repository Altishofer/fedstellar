// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;
// EVM-Version => PARIS, or else it will not work properly!

contract ReputationSystem {

    constructor() payable {}

    struct Edge {
        bool neighbor;
        uint256[] opinions;
        uint256 stddev_to_neighbor;
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
        uint centrality;
        uint difference;
        uint avg_difference;
        uint index;
        uint stddev_opinions;
    }

    struct Layer {
        string name;
        int256[] values;
    }

    // Events for debugging
    event Debug(string what, uint256 variable);
    event Debug(string what, bool variable);
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
                adj_matrix[y].push(Edge(false, new uint256[](0), 0));
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

    function aggregate(Layer[] memory a, Layer[] memory b) public returns (Layer[] memory){

        uint256 max_len = a.length > b.length ? a.length : b.length;
        uint256 min_len = a.length < b.length ? a.length : b.length;

        Layer[] memory result = new Layer[](max_len);


        for (uint256 i=0; i<min_len; i++){

            uint256 current_max_len = a[i].values.length > b[i].values.length ? a[i].values.length : b[i].values.length;
            uint256 current_min_len = a[i].values.length < b[i].values.length ? a[i].values.length : b[i].values.length;

            require(keccak256(bytes(a[i].name)) == keccak256(bytes(b[i].name)), "layers are not the same");

            Layer memory new_layer = Layer(a[i].name, new int256[](current_max_len));

            for (uint idx=0; idx<current_min_len; idx++){

                new_layer.values[idx] = (int256(MULTIPLIER) * a[i].values[idx] + int256(MULTIPLIER) * b[i].values[idx]) / 2;
                new_layer.values[idx] /= int256(MULTIPLIER);

            }
            result[i] = new_layer;
        }

        return result;
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
            require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors (rate_neighbors)");

            // push opinion value to Edge object in adj_matrix
            Edge storage edge = adj_matrix[index_sender][index_target];

            //edge.opinions.push(opinion);
            if (neighbor.value > 0){
                edge.opinions.push(neighbor.value);
            }
        }

        return true;
    }

    function confirm_registration() public view returns(bool){
        return accounts[msg.sender].registered;
    }

    function valid_neighbors(uint node_a, uint node_b) public view returns (bool){
        return (adj_matrix[node_a][node_b].neighbor && adj_matrix[node_b][node_a].neighbor) || node_a == node_b;
    }

    // function getHistory(uint a, uint b) public view returns (uint[] memory){
    //     return adj_matrix[a][b].opinions;
    // }

    function compute_difference(uint256 a, uint256 b) public returns (uint){

        require(valid_neighbors(a, b), "Nodes are not confirmed neighbors (compute_difference)");

        uint256[] memory opinions_a = adj_matrix[a][b].opinions;
        uint256[] memory opinions_b = adj_matrix[b][a].opinions;

        uint256 p_a;
        uint256 p_b;

        uint256 differences = abs(int256(opinions_a.length) - int256(opinions_b.length));

        while (p_a < opinions_a.length && p_b < opinions_b.length){

            if (opinions_a[p_a] == opinions_b[p_b]){
                p_a++;
                p_b++;
            } else if (p_b + 1 < opinions_b.length && opinions_a[p_a] == opinions_b[p_b +1]){
                differences++;
                p_b++;
            } else if (p_a + 1 < opinions_a.length && opinions_b[p_b] == opinions_a[p_a +1]){
                differences++;
                p_a++;
            } else {
                p_a++;
                p_b++;
                differences += 2;
            }
        }

        emit Debug("differences", differences);

        return differences;
    }


    function stddev_opinions(uint256 a, uint256 b) public returns (uint){

        require(valid_neighbors(a, b), "Nodes are not confirmed neighbors (compute_difference)");

        uint256[] memory opinions_a = adj_matrix[a][b].opinions;
        uint256[] memory opinions_b = adj_matrix[b][a].opinions;

        uint256 min_len = opinions_a.length > opinions_b.length ? opinions_b.length : opinions_a.length;

        if (min_len <= 0){
            return 0;
        }

        uint256[] memory differences = new uint256[](min_len);
        uint256 sum_differences = 0;

        for (uint256 i=0; i < differences.length; i++){
            differences[i] = abs(int256(opinions_a[i]) - int256(opinions_b[i])) * MULTIPLIER;
            sum_differences += differences[i];
        }


        require(differences.length > 0, "differences.length == 0");

        uint256 avg_differences = sum_differences / differences.length;

        uint256 variance = 0;
        for (uint i=0; i<differences.length; i++){
            uint256 diff = abs(int256(avg_differences) - int256(differences[i]));
            variance += diff * diff;
        }

        variance /= differences.length;

        if (variance <= 0){
            return 0;
        }
        require(variance > 0, "variance == 0");
        uint stddev = sqrt(variance) / MULTIPLIER;

        adj_matrix[a][b].stddev_to_neighbor = stddev;
        adj_matrix[b][a].stddev_to_neighbor = stddev;

        return stddev;
    }

    function malicious(uint256 a) public returns (uint256){

        uint256[] memory differences = new uint256[](nodes.length);
        uint256 neighbors_cnt;
        uint256 neighbors_flagged;
        for (uint256 n=0; n<nodes.length; n++){
            if (a == n || valid_neighbors(a, n) == false){
                continue;
            }
            require(valid_neighbors(a, n), "Malicious, nodes are not valid neighbors");
            require(a != n, "Malicious, a != n is false");
            differences[n] = compute_difference(a, n);
            neighbors_cnt++;
            if (differences[n] > 1){
                neighbors_flagged++;
            }
        }

        return neighbors_flagged > 0 ? neighbors_cnt / neighbors_flagged : 0;
    }

    function get_reputations(string[] memory neighbors) public returns (DebugDict[] memory){

        DebugDict[] memory reputations = new DebugDict[](neighbors.length);
        uint256 sum_reputations = 0;
        uint256 index_sender = accounts[msg.sender].index;

        for (uint j=0; j<neighbors.length; j++){

            string memory name_target = neighbors[j];

            // get adj_matrix indexes of registered participants
            require(accounts[msg.sender].registered, "msg.sender did not register the neighborhood.");
            require(names[name_target].registered, "target node did not register their neighborhood.");

            // get adj_matrix indexes of registered participants
            uint256 index_target = names[name_target].index;

            // check if nodes did both confirm their neighborhood
            require(valid_neighbors(index_sender, index_target), "Nodes are not confirmed neighbors (get_reputations)");

            uint256[] memory opinions = new uint256[](nodes.length);

            for (uint256 i = 0; i < nodes.length; i++) {
                uint256[] memory participant_history = adj_matrix[i][index_target].opinions;
                uint256 hist_len = participant_history.length;

                if (hist_len <= 0) {continue;}

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

                require(uint256(hist_included) > 0, "uint256(hist_included) <= 0");
                opinions[i] = sum / uint256(hist_included);
            }

            uint256 n_opinions;
            uint256 sum_opinions;

            for (uint256 i = 0; i < opinions.length; i++) {
                uint256 opinion = opinions[i];
                if (opinion > 0) {
                    sum_opinions += opinion;
                    n_opinions++;
                }
            }

            uint256 final_opinion;
            if (n_opinions > 0 && sum_opinions > 0) {
                final_opinion = uint256(sum_opinions / n_opinions);
                require(final_opinion > 0, "final opinion is zero");
            } else {
                final_opinion = 10 * MULTIPLIER;
            }

            reputations[j] = DebugDict(name_target, final_opinion, 0, 0, 0, 0, 0, 0, 0, index_target, 0);
            sum_reputations += final_opinion;
        }

        emit Debug("sum_reputations", sum_reputations);

        if (sum_reputations <= 0 || reputations.length <= 1) {
            for (uint i = 0; i < reputations.length; i++){
                reputations[i].reputation /= MULTIPLIER;
            }
            return reputations;
        }

        require(reputations.length > 1, "reputations.length <= 1");
        uint256 avg = sum_reputations / reputations.length;
        uint256 stddev = 0;

        emit Debug("avg", avg);

        for (uint256 i = 0; i < reputations.length; i++) {
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

        for (uint256 i = 0; i < reputations.length; i++) {

            uint256 cntt = abs(int256(avg) - int256(reputations[i].reputation)) / stddev;

            if (
                    stddev > 0 &&
                    reputations[i].reputation < avg &&
                    cntt >= 1
                ){

                uint256 cntt_red = (abs(int256(avg) - int256(reputations[i].reputation)) / stddev) +1;
                require(cntt_red >= 2, "stddev <= 2");

                uint f = cntt_red * (MULTIPLIER + nodes[reputations[i].index].centrality);
                require(f > 0, "f <= 0");
                emit Debug("f", f);

                reputations[i].final_reputation = reputations[i].reputation / f;

            } else {
                reputations[i].final_reputation = reputations[i].reputation / MULTIPLIER;
            }

            DebugDict memory target = reputations[i];

            target.reputation /= MULTIPLIER;
            target.stddev_count = cntt;
            target.stddev = stddev / MULTIPLIER;
            target.avg = avg / MULTIPLIER;
            target.centrality = nodes[target.index].centrality / (MULTIPLIER / 100);
            target.difference = compute_difference(index_sender, target.index);
            target.avg_difference = malicious(target.index);
            // target.stddev_opinions = stddev_opinions(index_sender, target.index);

            reputations[i] = target;

            // if (compute_difference(index_sender, index_target) > 1 || malicious(index_target)){
            //     final_opinion = 0;
            // }

            emit Debug("final_reputation", reputations[i].final_reputation);
            emit Debug("stddev_count", reputations[i].stddev_count);
            emit Debug("stddev", reputations[i].stddev);
            emit Debug("avg", reputations[i].avg);
            emit Debug("reputation", reputations[i].reputation);
            emit Debug("centrality", reputations[i].centrality);
            emit Debug("difference", reputations[i].difference);
            emit Debug("malicious", reputations[i].avg_difference);
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

    // function get_centrality() public view returns (uint[] memory){
    //     uint256[] memory ret = new uint256[](nodes.length);
    //     for (uint256 i=0; i<nodes.length; i++){
    //         ret[i] = nodes[i].centrality;
    //     }
    //     return ret;
    // }

}