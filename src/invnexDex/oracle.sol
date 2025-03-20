// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {Chainlink, ChainlinkClient} from "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract APIConsumer is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    mapping(address => uint256) public prices; // Stores prices for each token
    mapping(address => uint256) public lastUpdated; // Stores last updated timestamp
    mapping(bytes32 => address) private requestToToken; // Maps request IDs to tokens

    bytes32 private jobId;
    uint256 private fee;

    event RequestPrice(bytes32 indexed requestId, address indexed token, uint256 price, uint256 timestamp);

    constructor() ConfirmedOwner(msg.sender) {
        _setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789); // LINK token on Sepolia
        _setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD); // Chainlink Oracle
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0.1 LINK
    }

    function requestPriceData(address token, string memory symbol) public returns (bytes32 requestId) {
        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );

        string memory apiUrl = string(abi.encodePacked(
            "https://min-api.cryptocompare.com/data/pricemultifull?fsyms=",
            symbol,
            "&tsyms=USD"
        ));
        req._add("get", apiUrl);

        string memory path = string(abi.encodePacked("RAW.", symbol, ".USD.PRICE"));
        req._add("path", path);

        int256 timesAmount = 10 ** 18;
        req._addInt("times", timesAmount);

        requestId = _sendChainlinkRequest(req, fee);
        requestToToken[requestId] = token;
        return requestId;
    }

    function fulfill(bytes32 _requestId, uint256 _price) public recordChainlinkFulfillment(_requestId) {
        address token = requestToToken[_requestId];
        require(token != address(0), "Invalid token address");

        prices[token] = _price;
        lastUpdated[token] = block.timestamp;
        emit RequestPrice(_requestId, token, _price, block.timestamp);
    }

    function setManualPrice(address token, uint256 price) external {
        require(token != address(0), "Invalid token address");
        prices[token] = price;
        lastUpdated[token] = block.timestamp;
        emit RequestPrice(0, token, price, block.timestamp);
    }

    function getPrice(address _token) public view returns (uint256) {
        require(prices[_token] > 0, "Price not available");
        return prices[_token];
    }

    function getLastUpdatedPrice(address _token) public view returns (uint256 price, uint256 timestamp) {
        require(prices[_token] > 0, "Price not available");
        return (prices[_token], lastUpdated[_token]);
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
    }
}
