pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@xcute/contracts/interfaces/IJobsRegistry.sol";
import "./interfaces/kpi-tokens/IKPIToken.sol";
import "./interfaces/oracles/IOracle.sol";
import "./interfaces/IOraclesManager.sol";
import "./interfaces/IKPITokensFactory.sol";
import "./libraries/OracleTemplateSetLibrary.sol";

/**
 * @title OraclesManager
 * @dev OraclesManager contract
 * @author Federico Luzzi - <fedeluzzi00@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
contract OraclesManager is Ownable, IOraclesManager {
    using SafeERC20 for IERC20;
    using OracleTemplateSetLibrary for IOraclesManager.EnumerableTemplateSet;

    address public factory;
    address public workersJobsRegistry;
    IOraclesManager.EnumerableTemplateSet private templates;

    error NonExistentTemplate();
    error ZeroAddressFactory();
    error Forbidden();
    error AlreadyAdded();
    error ZeroAddressTemplate();
    error NotAnUpgrade();
    error ZeroAddressWorkersJobsRegistry();
    error InvalidSpecification();
    error InvalidAutomationParameters();

    constructor(address _factory, address _workersJobsRegistry) {
        if (_factory == address(0)) revert ZeroAddressFactory();
        factory = _factory;
        workersJobsRegistry = _workersJobsRegistry;
    }

    function salt(
        address _automationFundingToken,
        uint256 _automationFundingAmount,
        bytes memory _initializationData
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _automationFundingToken,
                    _automationFundingAmount,
                    _initializationData
                )
            );
    }

    function predictInstanceAddress(
        uint256 _id,
        address _automationFundingToken,
        uint256 _automationFundingAmount,
        bytes memory _initializationData
    ) external view returns (address) {
        return
            Clones.predictDeterministicAddress(
                templates.get(_id).addrezz,
                salt(
                    _automationFundingToken,
                    _automationFundingAmount,
                    _initializationData
                ),
                address(this)
            );
    }

    function instantiate(
        uint256 _id,
        address _automationFundingToken,
        uint256 _automationFundingAmount,
        bytes memory _initializationData
    ) external override returns (address) {
        if (!IKPITokensFactory(factory).created(msg.sender)) revert Forbidden();
        address _instance = Clones.cloneDeterministic(
            templates.get(_id).addrezz,
            salt(
                _automationFundingToken,
                _automationFundingAmount,
                _initializationData
            )
        );
        if (
            _automationFundingAmount > 0 &&
            _automationFundingToken != address(0) &&
            workersJobsRegistry != address(0)
        ) {
            IJobsRegistry(workersJobsRegistry).addJob(_instance);
            _ensureJobsRegistryAllowance(
                _automationFundingToken,
                _automationFundingAmount
            );
            IJobsRegistry(workersJobsRegistry).addCredit(
                _instance,
                _automationFundingToken,
                _automationFundingAmount
            );
        }
        IOracle(_instance).initialize(
            msg.sender,
            templates.get(_id),
            _initializationData
        );
        return _instance;
    }

    function addTemplate(
        address _template,
        bool _automatable,
        string calldata _specification
    ) external override {
        if (msg.sender != owner()) revert Forbidden();
        templates.add(_template, _automatable, _specification);
    }

    function removeTemplate(uint256 _id) external override {
        if (msg.sender != owner()) revert Forbidden();
        templates.remove(_id);
    }

    function updateTemplateSpecification(
        uint256 _id,
        string calldata _newSpecification
    ) external override {
        if (msg.sender != owner()) revert Forbidden();
        templates.get(_id).specification = _newSpecification;
    }

    function updgradeTemplate(
        uint256 _id,
        address _newTemplate,
        string calldata _newSpecification
    ) external override {
        if (msg.sender != owner()) revert Forbidden();
        templates.upgrade(_id, _newTemplate, _newSpecification);
    }

    function _ensureJobsRegistryAllowance(
        address _token,
        uint256 _minimumAmount
    ) internal {
        if (
            _token != address(0) &&
            workersJobsRegistry != address(0) &&
            _minimumAmount > 0
        )
            IERC20(_token).approve(
                workersJobsRegistry,
                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
            );
    }

    function template(uint256 _id)
        external
        view
        override
        returns (IOraclesManager.Template memory)
    {
        return templates.get(_id);
    }

    function templatesAmount() external view override returns (uint256) {
        return templates.size();
    }

    function templatesSlice(uint256 _fromIndex, uint256 _toIndex)
        external
        view
        override
        returns (IOraclesManager.Template[] memory)
    {
        return templates.enumerate(_fromIndex, _toIndex);
    }
}