// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "@jbx-protocol/contracts-v1/contracts/interfaces/IProjects.sol";
import "@jbx-protocol/contracts-v1/contracts/interfaces/IFundingCycles.sol";
import "@jbx-protocol/contracts-v1/contracts/interfaces/IModStore.sol";
import "@jbx-protocol/contracts-v1/contracts/interfaces/ITerminal.sol";
import "@jbx-protocol/contracts-v1/contracts/interfaces/ITerminalV1.sol";
import "@jbx-protocol/contracts-v1/contracts/interfaces/ITerminalV1_1.sol";

import "@jbx-protocol/contracts-v2/contracts/interfaces/IJBController.sol"; 
import "@jbx-protocol/contracts-v2/contracts/interfaces/IJBDirectory.sol"; 
import "@jbx-protocol/contracts-v2/contracts/interfaces/IJBSplitsStore.sol"; 
import "@jbx-protocol/contracts-v2/contracts/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";
import "@jbx-protocol/contracts-v2/contracts/libraries/JBSplitsGroups.sol";
import "@jbx-protocol/contracts-v2/contracts/libraries/JBConstants.sol";
import "@jbx-protocol/contracts-v2/contracts/libraries/JBTokens.sol";
import "@jbx-protocol/contracts-v2/contracts/libraries/JBCurrencies.sol";

contract DeprecateSimulateScript is Script, Test {
    address immutable fundedWallet = address(0x0Bc1b73d735083Adb4f26671BC90B68a86B33dE4);

     // JB Multisig
    address immutable multisig = address(0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e);   
    uint256 immutable projectId = 1;

    // JB V1 Governance contract
    Governance immutable public governance = Governance(0xAc43e14c018490D045a774008648c701cda8C6b3);

    // V1 Stores
    IProjects immutable public projectsV1 = IProjects(0x9b5a4053FfBB11cA9cd858AAEE43cc95ab435418);    
    IFundingCycles immutable public fundingCycles = IFundingCycles(0xf507B2A1dD7439201eb07F11E1d62AfB29216e2E);
    IModStore immutable public modStore = IModStore(0xB9E4B658298C7A36BdF4C2832042A5D6700c3Ab8);

    // V2 Stores
    IJBController immutable public controller = IJBController(0x4e3ef8AFCC2B52E4e704f4c8d9B7E7948F651351);
    IJBDirectory immutable public directory = IJBDirectory(0xCc8f7a89d89c2AB3559f484E0C656423E979ac9C);
    IJBSplitsStore immutable public splitStore = IJBSplitsStore(0xFBE1075826B7FFd898cf8D944885ba6a8D714A7F);

    // Terminals
    ITerminal immutable public terminalV1 = ITerminal(0xd569D3CCE55b71a8a3f3C418c329A66e5f714431);
    ITerminalV1_1 immutable public terminalV1_1 = ITerminalV1_1(0x981c8ECD009E3E84eE1fF99266BF1461a12e5c68);
    IJBPayoutRedemptionPaymentTerminal immutable public terminalV2 = IJBPayoutRedemptionPaymentTerminal(0x7Ae63FBa045Fec7CaE1a75cF7Aa14183483b8397);
    
    function setUp() public {}

    function run() public {
        // Forge doesn't realize that this wallet will be funded on the tenderly RPC
        // So we fund the wallet by having the WETH address send it money
        vm.broadcast(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        fundedWallet.call{value: 100 ether}('');

        // Step 1: Migrate to V1.1
        vm.broadcast(multisig);
        terminalV1.migrate(
            projectId,
            ITerminal(address(terminalV1_1))
        );

        //Step 2: Turn off V1 fees
        vm.broadcast(multisig);
        governance.setFee(ITerminalV1(address(terminalV1)), 0);

        // Step 3: Turn off V1.1 fees
        vm.broadcast(multisig);
        terminalV1_1.setFee(0);

        // Step 4: Turn off V2 fees
        vm.broadcast(multisig);
        terminalV2.setFee(0);

        // Get the active V1 funding cycle
        FundingCycle memory _fc = fundingCycles.currentOf(projectId);
        // Get the payoutMods
        PayoutMod[] memory _payoutMods = modStore.payoutModsOf(projectId, _fc.configured);
        // Get the ticketMods
        TicketMod[] memory _ticketMods = modStore.ticketModsOf(projectId, _fc.configured);

        // Step 5: configure the V1.1 funding cycle
        vm.broadcast(multisig);
        terminalV1_1.configure(
            projectId,
            FundingCycleProperties({
                target: _fc.target,
                currency: _fc.currency,
                duration: _fc.duration,
                cycleLimit: _fc.cycleLimit,
                discountRate: _fc.discountRate,
                ballot: _fc.ballot
            }),
            FundingCycleMetadata2({
                reservedRate: 0,
                bondingCurveRate: 0,
                reconfigurationBondingCurveRate: 0,
                payIsPaused: true,
                ticketPrintingIsAllowed: true,
                treasuryExtension: ITreasuryExtension(address(0))
            }),
            _payoutMods,
            _ticketMods
        );

        // Get the controller of V2
        IJBController _controller = IJBController(directory.controllerOf(projectId));
        (JBFundingCycle memory fundingCycle, JBFundingCycleMetadata memory metadata) = _controller.currentFundingCycleOf(projectId);

        // Modify the metadata to pausePay
        metadata.pausePay = true;

        // Build the JBSplits
        JBGroupedSplits[] memory _splits = new JBGroupedSplits[](2);
        _splits[0] = JBGroupedSplits({
            group: JBSplitsGroups.ETH_PAYOUT,
            splits: splitStore.splitsOf(projectId, fundingCycle.configuration, JBSplitsGroups.ETH_PAYOUT)
        });

        _splits[1] = JBGroupedSplits({
            group: JBSplitsGroups.RESERVED_TOKENS,
            splits: splitStore.splitsOf(projectId, fundingCycle.configuration, JBSplitsGroups.RESERVED_TOKENS)
        });

        // Step 6: Configure a V2 cycle with pausePay
        vm.broadcast(multisig);
        _controller.reconfigureFundingCyclesOf(
            projectId,
            JBFundingCycleData({
                duration: fundingCycle.duration,
                weight: fundingCycle.weight,
                discountRate: fundingCycle.discountRate,
                ballot: fundingCycle.ballot
            }),
            metadata,
            0,
            _splits,
            new JBFundAccessConstraints[](0),
            ""
        );

        // Create a new user that will create projects etc.
        address _newUser = address(0xbeef);
        // Fund the wallet so they can pay for gas
        vm.broadcast(fundedWallet);
        fundedWallet.call{value: 1 ether}('');

        // Run some tests
        testV1(_newUser);
        testV1_1(_newUser);
        testV2(_newUser);
    }

    /**
     * Tests
    */

    function testV1(address _projectOwner) public {
        // Create project that will get paid by another project
        uint256 _recipientProject = _createV1Project(_projectOwner, 'recipient_project', new PayoutMod[](0));

        // Create the payout mods
        PayoutMod[] memory _payoutMods = new PayoutMod[](2);
        _payoutMods[0] = PayoutMod({
            preferUnstaked: false,
            percent: 4_000,
            lockedUntil: 0,
            beneficiary: payable(_projectOwner),
            allocator: IModAllocator(address(0)),
            projectId: 0
        });
        _payoutMods[1] = PayoutMod({
            preferUnstaked: false,
            percent: 5_000,
            lockedUntil: 0,
            beneficiary: payable(_projectOwner),
            allocator: IModAllocator(address(0)),
            projectId: uint56(_recipientProject)
        });

        uint256 _optimisticProjectId = _createV1Project(_projectOwner, 'payout_project', _payoutMods);

        // Pay the project
        vm.broadcast(fundedWallet);
        uint256 _fundingCycleId = terminalV1.pay{value: 10 ether}(_optimisticProjectId, fundedWallet, '', false);

        // Assert that the the fee is 0
        vm.expectEmit(true, true, true, true);
        emit Tap( _fundingCycleId, _optimisticProjectId, _projectOwner, 10 ether, 0, 10 ether, 1 ether, 0 ether, _projectOwner);

        // Distribute funds
        vm.broadcast(_projectOwner);
        ITerminalV1(address(terminalV1)).tap(_optimisticProjectId, 10 ether, 0, 10 ether);

        // Assert that the project got paid the expected amount
        assertEq(
            ITerminalV1(address(terminalV1)).balanceOf(_recipientProject),
            5 ether
        );
    }

     function testV1_1(address _projectOwner) public {
        // Create project that will get paid by another project
        uint256 _recipientProject = _createV1_1Project(_projectOwner, 'recipient_project_1_1', new PayoutMod[](0));

        // Create the payout mods
        PayoutMod[] memory _payoutMods = new PayoutMod[](2);
        _payoutMods[0] = PayoutMod({
            preferUnstaked: false,
            percent: 4_000,
            lockedUntil: 0,
            beneficiary: payable(_projectOwner),
            allocator: IModAllocator(address(0)),
            projectId: 0
        });
        _payoutMods[1] = PayoutMod({
            preferUnstaked: false,
            percent: 5_000,
            lockedUntil: 0,
            beneficiary: payable(_projectOwner),
            allocator: IModAllocator(address(0)),
            projectId: uint56(_recipientProject)
        });

        uint256 _optimisticProjectId = _createV1_1Project(_projectOwner, 'payout_project_1_1', _payoutMods);

        // Pay the project
        vm.broadcast(fundedWallet);
        uint256 _fundingCycleId = ITerminal(address(terminalV1_1)).pay{value: 10 ether}(_optimisticProjectId, fundedWallet, '', false);

        // Assert that the the fee is 0
        vm.expectEmit(true, true, true, true);
        emit Tap( _fundingCycleId, _optimisticProjectId, _projectOwner, 10 ether, 0, 10 ether, 1 ether, 0 ether, _projectOwner);

        // Distribute funds
        vm.broadcast(_projectOwner);
        terminalV1_1.tap(_optimisticProjectId, 10 ether, 0, 10 ether);

        // Assert that the project got paid the expected amount
        assertEq(
            terminalV1_1.balanceOf(_recipientProject),
            5 ether
        );
    }

    function testV2(address _projectOwner) public {
        // Create project that will get paid by another project
        uint256 _recipientProject = _createV2Project(_projectOwner, new JBGroupedSplits[](0));

        // Create the splits
        JBSplit[] memory _splits = new JBSplit[](2);
        _splits[0] = JBSplit({
            preferClaimed: false,
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT / 10 * 9,
            projectId: _recipientProject,
            beneficiary: payable(_projectOwner),
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });
        _splits[1] = JBSplit({
            preferClaimed: false,
            preferAddToBalance: false,
            percent: JBConstants.SPLITS_TOTAL_PERCENT / 10,
            projectId: 0,
            beneficiary: payable(_projectOwner),
            lockedUntil: 0,
            allocator: IJBSplitAllocator(address(0))
        });

        // Create the grouped splits
        JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1);
        _groupedSplits[0] = JBGroupedSplits({
            group: JBSplitsGroups.ETH_PAYOUT,
            splits: _splits
        });

        // Create the project that will get paid and will forward part of the ETH on distribution.
        uint256 _payProjectId = _createV2Project(_projectOwner, _groupedSplits);

        // We need the funding cycle configuration number of the PayProject
        (JBFundingCycle memory _ppFC,,) = controller.latestConfiguredFundingCycleOf(_payProjectId);
        // We need the funding cycle configuration number of the recipient project
        (JBFundingCycle memory _rpFC,,) = controller.latestConfiguredFundingCycleOf(_payProjectId);

        // Pay the project
        vm.broadcast(fundedWallet);
        terminalV2.pay{value: 10 ether}(
            _payProjectId,
            10 ether,
            JBTokens.ETH,
            _projectOwner,
            0,
            false,
            "",
            bytes("")
        ); 

        // Assert that the project got paid the expected amount
        vm.expectEmit(true, true, true, true);
        emit Pay(
            _rpFC.configuration,
            1,
            _recipientProject,
            address(terminalV2),
            address(_projectOwner),
            9 ether,
            0,
            "",
            abi.encode(_payProjectId),
            address(_projectOwner)
        );

        // Assert that the the fee is 0
        vm.expectEmit(true, true, true, true);
        emit DistributePayouts(
            _ppFC.configuration,
            1,
            _payProjectId,
            address(_projectOwner),
            10 ether,
            10 ether,
            0 ether,
            0 ether,
            "",
            address(_projectOwner)
        );

        // Distribute the funds
        vm.broadcast(_projectOwner);
        terminalV2.distributePayoutsOf(
            _payProjectId,
            10 ether,
            JBCurrencies.ETH,
            JBTokens.ETH,
            0,
            ""
        );
    }

    /**
     * Helpers
     */

    function _createV1Project(address _projectOwner, bytes32 _handle, PayoutMod[] memory _payoutMods) internal returns(uint256 _projectId) {
        _projectId = projectsV1.count() + 1;

        // Create a new project
        vm.broadcast(_projectOwner);
        ITerminalV1(address(terminalV1)).deploy(
            _projectOwner,
            _handle,
            '',
            FundingCycleProperties({
                target: 10 ether,
                currency: 0,
                duration: 14,
                cycleLimit: 0,
                discountRate: 0,
                ballot: IFundingCycleBallot(0x6d6da471703647Fd8b84FFB1A29e037686dBd8b2)
            }),
            FundingCycleMetadata({
                reservedRate: 0,
                bondingCurveRate: 0,
                reconfigurationBondingCurveRate: 0
            }),
            _payoutMods,
            new TicketMod[](0)
        );
    }

    /**
     * Helpers
     */

    function _createV1_1Project(address _projectOwner, bytes32 _handle, PayoutMod[] memory _payoutMods) internal returns(uint256 _projectId) {
        _projectId = projectsV1.count() + 1;

        // Create a new project
        vm.broadcast(_projectOwner);
        terminalV1_1.deploy(
            _projectOwner,
            _handle,
            '',
            FundingCycleProperties({
                target: 10 ether,
                currency: 0,
                duration: 14,
                cycleLimit: 0,
                discountRate: 0,
                ballot: IFundingCycleBallot(0x6d6da471703647Fd8b84FFB1A29e037686dBd8b2)
            }),
            FundingCycleMetadata2({
                reservedRate: 0,
                bondingCurveRate: 0,
                reconfigurationBondingCurveRate: 0,
                payIsPaused: false,
                ticketPrintingIsAllowed: false,
                treasuryExtension: ITreasuryExtension(address(0))
            }),
            _payoutMods,
            new TicketMod[](0)
        );
    }

    function _createV2Project(address _projectOwner, JBGroupedSplits[] memory _groupedSplits) internal returns (uint256 _projectId) {
        // Initialize the terminal array .
        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = IJBPaymentTerminal(address(terminalV2));

        JBFundAccessConstraints[] memory _fundAccessConstraints = new JBFundAccessConstraints[](1);
        _fundAccessConstraints[0] = JBFundAccessConstraints({
            terminal: IJBPaymentTerminal(address(terminalV2)),
            token: JBTokens.ETH,
            distributionLimit: 10 ether,
            distributionLimitCurrency: JBCurrencies.ETH,
            overflowAllowance: 0,
            overflowAllowanceCurrency: JBCurrencies.ETH
        });

        // Create a new project
        vm.broadcast(_projectOwner);
        return controller.launchProjectFor(
            // Project is owned by this contract.
            _projectOwner,
            JBProjectMetadata({
                content: '',
                domain: 0
            }),
            JBFundingCycleData ({
                duration: 14,
                // Don't mint project tokens.
                weight: 0,
                discountRate: 0,
                ballot: IJBFundingCycleBallot(address(0))
            }),
            JBFundingCycleMetadata ({
                global: JBGlobalFundingCycleMetadata({
                    allowSetTerminals: false,
                    allowSetController: false
                }),
                reservedRate: 0,
                redemptionRate: 0,
                ballotRedemptionRate: 0,
                pausePay: false,
                pauseDistributions: false,
                pauseRedeem: false,
                pauseBurn: false,
                allowMinting: false,
                allowChangeToken: false,
                allowTerminalMigration: false,
                allowControllerMigration: false,
                holdFees: false,
                useTotalOverflowForRedemptions: false,
                useDataSourceForPay: false,
                useDataSourceForRedeem: false,
                dataSource: address(0)
            }),
            0,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ''
        );
    }

    /**
     * V1 Events
     */
    event Tap(
        uint256 indexed fundingCycleId,
        uint256 indexed projectId,
        address indexed beneficiary,
        uint256 amount,
        uint256 currency,
        uint256 netTransferAmount,
        uint256 beneficiaryTransferAmount,
        uint256 govFeeAmount,
        address caller
    );

    event Pay(
        uint256 indexed fundingCycleId,
        uint256 indexed projectId,
        address indexed beneficiary,
        uint256 amount,
        string note,
        address caller
    );

    /**
     * V2 Events
     */

    event DistributePayouts(
        uint256 indexed fundingCycleConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address beneficiary,
        uint256 amount,
        uint256 distributedAmount,
        uint256 fee,
        uint256 beneficiaryDistributionAmount,
        string memo,
        address caller
    );

    event Pay(
        uint256 indexed fundingCycleConfiguration,
        uint256 indexed fundingCycleNumber,
        uint256 indexed projectId,
        address payer,
        address beneficiary,
        uint256 amount,
        uint256 beneficiaryTokenCount,
        string memo,
        bytes metadata,
        address caller
    );
}

interface Governance {
     /** 
      @notice Sets the fee of the TerminalV1.
      @param _terminalV1 The terminalV1 to change the fee of.
      @param _fee The new fee.
    */
    function setFee(ITerminalV1 _terminalV1, uint256 _fee) external;
}