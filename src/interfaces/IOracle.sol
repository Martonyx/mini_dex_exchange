// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAPIConsumer {
    function requestPriceData(address token, string memory symbol) external returns (bytes32 requestId);

    /**
     * @notice Returns the last fetched price of a token
     * @param token Address of the token
     * @return price Token price in USD (multiplied by 10^18)
     */
    function getPrice(address token) external view returns (uint256 price);

    /**
     * @notice Returns the last fetched price of a token along with the timestamp
     * @param token Address of the token
     * @return price Token price in USD (multiplied by 10^18)
     * @return lastUpdated Timestamp of the last price update
     */
    function getLastUpdatedPrice(address token) external view returns (uint256 price, uint256 lastUpdated);

    /**
     * @notice Allows contract owner to withdraw LINK tokens
     */
    function withdrawLink() external;
}