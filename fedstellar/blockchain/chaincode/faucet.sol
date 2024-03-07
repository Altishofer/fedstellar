// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract Faucet {
    uint256 public store;
    string[] public strList;

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
