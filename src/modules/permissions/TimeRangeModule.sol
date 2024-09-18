// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {_packValidationData} from "@eth-infinitism/account-abstraction/core/Helpers.sol";
import {PackedUserOperation} from "@eth-infinitism/account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {IModule} from "@erc6900/reference-implementation/interfaces/IModule.sol";
import {IValidationHookModule} from "@erc6900/reference-implementation/interfaces/IValidationHookModule.sol";

import {BaseModule} from "../../modules/BaseModule.sol";

contract TimeRangeModule is IValidationHookModule, BaseModule {
    struct TimeRange {
        uint48 validUntil;
        uint48 validAfter;
    }

    mapping(uint32 entityId => mapping(address account => TimeRange)) public timeRanges;

    error TimeRangeNotValid();

    function onInstall(bytes calldata data) external override {
        (uint32 entityId, uint48 validUntil, uint48 validAfter) = abi.decode(data, (uint32, uint48, uint48));

        setTimeRange(entityId, validUntil, validAfter);
    }

    function onUninstall(bytes calldata data) external override {
        uint32 entityId = abi.decode(data, (uint32));

        delete timeRanges[entityId][msg.sender];
    }

    function preUserOpValidationHook(uint32 entityId, PackedUserOperation calldata, bytes32)
        external
        view
        override
        returns (uint256)
    {
        // todo: optimize between memory / storage
        TimeRange memory timeRange = timeRanges[entityId][msg.sender];
        return _packValidationData({
            sigFailed: false,
            validUntil: timeRange.validUntil,
            validAfter: timeRange.validAfter
        });
    }

    function preRuntimeValidationHook(uint32 entityId, address, uint256, bytes calldata, bytes calldata)
        external
        view
        override
    {
        TimeRange memory timeRange = timeRanges[entityId][msg.sender];
        if (block.timestamp > timeRange.validUntil || block.timestamp < timeRange.validAfter) {
            revert TimeRangeNotValid();
        }
    }

    // solhint-disable-next-line no-empty-blocks
    function preSignatureValidationHook(uint32, address, bytes32, bytes calldata) external pure override {}

    /// @inheritdoc IModule
    function moduleId() external pure returns (string memory) {
        return "alchemy.timerange-module.0.0.1";
    }

    function setTimeRange(uint32 entityId, uint48 validUntil, uint48 validAfter) public {
        timeRanges[entityId][msg.sender] = TimeRange(validUntil, validAfter);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BaseModule, IERC165)
        returns (bool)
    {
        return interfaceId == type(IValidationHookModule).interfaceId || super.supportsInterface(interfaceId);
    }
}
