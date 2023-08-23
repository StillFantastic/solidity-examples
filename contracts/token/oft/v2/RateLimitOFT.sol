// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./OFTV2.sol";


// TODO WARNING, not tested yet.. demonstration purposes ONLY
contract RateLimitOFT is OFTV2 {
    struct RateLimit {
        uint256 amountInFlight;
        uint256 lastDepositTime;
        uint256 limit;
        uint256 window;
    }

    struct RateLimitConfig {
        RateLimit rateLimit;
        uint16 dstChainId;
    }

    mapping(uint16 => RateLimit) public rateLimits;

    constructor(
        RateLimitConfig[] memory _rateLimitConfigs,
        string memory _name,
        string memory _symbol,
        uint8 _sharedDecimals,
        address _lzEndpoint
    ) OFTV2(_name, _symbol, _sharedDecimals, _lzEndpoint) {
        _setRateLimits(_rateLimitConfigs);
    }

    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner {
        _setRateLimits(_rateLimitConfigs);
    }

    function _setRateLimits(RateLimitConfig[] memory _rateLimitConfigs) internal {
        unchecked {
            for (uint i = 0; i < _rateLimitConfigs.length; i++) {
                RateLimit storage rl = rateLimits[_rateLimitConfigs[i].dstChainId];

                // @dev does NOT reset the amount/lastDepositTime of an existing amountInFlight/lastDepositTime
                rl.limit = _rateLimitConfigs[i].rateLimit.limit;
                rl.window = _rateLimitConfigs[i].rateLimit.window;
            }
        }
    }

    function getAmountCanBeSent(uint16 _dstChainId) external view returns (uint) {
        RateLimit memory rl = rateLimits[_dstChainId];
        return _amountCanBeSent(rl.amountInFlight, rl.lastDepositTime, rl.limit, rl.window);
    }

    function _amountCanBeSent(
        uint amountInFlight,
        uint lastDepositTime,
        uint limit,
        uint window
    ) internal view returns (uint amountCanBeSent) {
        uint256 timeSinceLastDeposit = block.timestamp - lastDepositTime;

        if (timeSinceLastDeposit >= window) {
            amountCanBeSent = limit;
        } else {
            unchecked {
            // @dev presumes linear decay
                uint256 currentAmountInFlight = amountInFlight * (window - timeSinceLastDeposit) / window;
            // @dev in the event the limit is lowered, and the 'in-flight' amount is higher than the limit, set to 0
                amountCanBeSent = limit < currentAmountInFlight ? 0 : limit - currentAmountInFlight;
            }
        }
    }

    function _checkAndUpdateRateLimit(uint16 _dstChainId, uint256 _amount) internal {
        RateLimit storage rl = rateLimits[_dstChainId];

        uint256 amountCanBeSent = _amountCanBeSent(rl.amountInFlight, rl.lastDepositTime, rl.limit, rl.window);
        require(_amount <= amountCanBeSent, "RateLimitOFT: max inflight reached");

        // update the storage to contain the new amount and current timestamp
        rl.amountInFlight += _amount;
        rl.lastDepositTime = block.timestamp;
    }

    function _debitFrom(address _from, uint16 _dstChainId, bytes32, uint _amount) internal override returns (uint) {
        address spender = _msgSender();
        if (_from != spender) _spendAllowance(_from, spender, _amount);

        _checkAndUpdateRateLimit(_dstChainId, _amount);

        _burn(_from, _amount);
        return _amount;
    }
}
