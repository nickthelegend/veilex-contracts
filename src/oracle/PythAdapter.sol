// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

contract PythAdapter {
    IPyth public immutable pyth;
    uint256 public constant MAX_PRICE_AGE = 60;

    constructor(address _pyth) {
        pyth = IPyth(_pyth);
    }

    function getPrice(bytes32 feedId) external view returns (int64 price, int32 expo, uint256 publishTime) {
        PythStructs.Price memory p = pyth.getPriceNoOlderThan(feedId, MAX_PRICE_AGE);
        return (p.price, p.expo, p.publishTime);
    }

    function updateAndGetPrice(bytes[] calldata updateData, bytes32 feedId)
        external
        payable
        returns (int64 price, int32 expo)
    {
        uint256 fee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeeds{value: fee}(updateData);
        PythStructs.Price memory p = pyth.getPriceNoOlderThan(feedId, MAX_PRICE_AGE);
        return (p.price, p.expo);
    }

    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256) {
        return pyth.getUpdateFee(updateData);
    }
}
