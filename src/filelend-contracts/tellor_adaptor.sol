// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "https://github.com/tellor-io/usingtellor/blob/master/contracts/UsingTellor.sol";

contract tellor_adaptor is UsingTellor {

    address filAddress;
    address stablecoinAddress;

    error oracleMalfunction();

    constructor(address payable _tellorAddress,
                address _filAddress,
                address _stablecoinAddress
    ) UsingTellor(_tellorAddress) {

        filAddress = _filAddress;
        stablecoinAddress = _stablecoinAddress;

    }

    function getPrice(address token) external view returns (uint256) {
      bytes memory _b = abi.encode("SpotPrice", abi.encode("fil", "usd"));
      bytes32 _filQueryId = keccak256(_b);

      uint256 _timestamp;
      bytes memory _value;

      (_value, _timestamp) = getDataBefore(_filQueryId, block.timestamp - 1 hours);
      
        if (token == filAddress){
            return abi.decode(_value, (uint256));
        }
        else { //stablecoin mock
            return 1000000000000000000;
        }
        
    }

}
