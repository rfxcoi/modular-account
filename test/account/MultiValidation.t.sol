// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@eth-infinitism/account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {IModularAccount, ModuleEntity} from "@erc6900/reference-implementation/interfaces/IModularAccount.sol";

import {ModularAccount} from "../../src/account/ModularAccount.sol";
import {ModuleEntityLib} from "../../src/helpers/ModuleEntityLib.sol";
import {ValidationConfigLib} from "../../src/helpers/ValidationConfigLib.sol";
import {SingleSignerValidationModule} from "../../src/modules/validation/SingleSignerValidationModule.sol";

import {AccountTestBase} from "../utils/AccountTestBase.sol";
import {TEST_DEFAULT_VALIDATION_ENTITY_ID} from "../utils/TestConstants.sol";

contract MultiValidationTest is AccountTestBase {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    SingleSignerValidationModule public validator2;

    address public owner2;
    uint256 public owner2Key;

    function setUp() public {
        validator2 = new SingleSignerValidationModule();

        (owner2, owner2Key) = makeAddrAndKey("owner2");
    }

    function test_overlappingValidationInstall() public {
        vm.prank(address(entryPoint));
        account1.installValidation(
            ValidationConfigLib.pack(address(validator2), TEST_DEFAULT_VALIDATION_ENTITY_ID, true, true, true),
            new bytes4[](0),
            abi.encode(TEST_DEFAULT_VALIDATION_ENTITY_ID, owner2),
            new bytes[](0)
        );

        ModuleEntity[] memory validations = new ModuleEntity[](2);
        validations[0] = _signerValidation;
        validations[1] = ModuleEntityLib.pack(address(validator2), TEST_DEFAULT_VALIDATION_ENTITY_ID);

        bytes4[] memory selectors0 = account1.getValidationData(validations[0]).selectors;
        bytes4[] memory selectors1 = account1.getValidationData(validations[1]).selectors;
        assertEq(selectors0.length, selectors1.length);
        for (uint256 i = 0; i < selectors0.length; i++) {
            assertEq(selectors0[i], selectors1[i]);
        }
    }

    function test_runtimeValidation_specify() public {
        test_overlappingValidationInstall();

        // Assert that the runtime validation can be specified.

        vm.prank(owner1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ModularAccount.RuntimeValidationFunctionReverted.selector,
                address(validator2),
                TEST_DEFAULT_VALIDATION_ENTITY_ID,
                abi.encodeWithSignature("NotAuthorized()")
            )
        );
        account1.executeWithAuthorization(
            abi.encodeCall(IModularAccount.execute, (address(0), 0, "")),
            _encodeSignature(
                ModuleEntityLib.pack(address(validator2), TEST_DEFAULT_VALIDATION_ENTITY_ID), GLOBAL_VALIDATION, ""
            )
        );

        vm.prank(owner2);
        account1.executeWithAuthorization(
            abi.encodeCall(IModularAccount.execute, (address(0), 0, "")),
            _encodeSignature(
                ModuleEntityLib.pack(address(validator2), TEST_DEFAULT_VALIDATION_ENTITY_ID), GLOBAL_VALIDATION, ""
            )
        );
    }

    function test_userOpValidation_specify() public {
        test_overlappingValidationInstall();

        // Assert that the userOp validation can be specified.

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(account1),
            nonce: 0,
            initCode: "",
            callData: abi.encodeCall(ModularAccount.execute, (address(0), 0, "")),
            accountGasLimits: _encodeGas(VERIFICATION_GAS_LIMIT, CALL_GAS_LIMIT),
            preVerificationGas: 0,
            gasFees: _encodeGas(1, 1),
            paymasterAndData: "",
            signature: ""
        });

        // Generate signature
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner2Key, userOpHash.toEthSignedMessageHash());
        userOp.signature = _encodeSignature(
            ModuleEntityLib.pack(address(validator2), TEST_DEFAULT_VALIDATION_ENTITY_ID),
            GLOBAL_VALIDATION,
            abi.encodePacked(r, s, v)
        );

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        entryPoint.handleOps(userOps, beneficiary);

        // Sign with owner 1, expect fail

        userOp.nonce = 1;
        (v, r, s) = vm.sign(owner1Key, userOpHash.toEthSignedMessageHash());
        userOp.signature = _encodeSignature(
            ModuleEntityLib.pack(address(validator2), TEST_DEFAULT_VALIDATION_ENTITY_ID),
            GLOBAL_VALIDATION,
            abi.encodePacked(r, s, v)
        );

        userOps[0] = userOp;
        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(userOps, beneficiary);
    }
}
