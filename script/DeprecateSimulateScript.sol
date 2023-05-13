// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "forge-std/Script.sol";

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

contract DeprecateSimulateScript is Script {
     // JB Multisig
    address immutable multisig = address(0xAF28bcB48C40dBC86f52D459A6562F658fc94B1e);   
    uint256 immutable projectId = 1;

    // JB V1 Governance contract
    Governance immutable public governance = Governance(0xAc43e14c018490D045a774008648c701cda8C6b3);

    // V1 Stores
    IFundingCycles immutable public fundingCycles = IFundingCycles(0xf507B2A1dD7439201eb07F11E1d62AfB29216e2E);
    IModStore immutable public modStore = IModStore(0xB9E4B658298C7A36BdF4C2832042A5D6700c3Ab8);

    // V2 Stores
    IJBDirectory immutable public directory = IJBDirectory(0xCc8f7a89d89c2AB3559f484E0C656423E979ac9C);
    IJBSplitsStore immutable public splitStore = IJBSplitsStore(0xFBE1075826B7FFd898cf8D944885ba6a8D714A7F);

    // Terminals
    ITerminal immutable public terminalV1 = ITerminal(0xd569D3CCE55b71a8a3f3C418c329A66e5f714431);
    ITerminalV1_1 immutable public terminalV1_1 = ITerminalV1_1(0x981c8ECD009E3E84eE1fF99266BF1461a12e5c68);
    IJBPayoutRedemptionPaymentTerminal immutable public terminalV2 = IJBPayoutRedemptionPaymentTerminal(0x7Ae63FBa045Fec7CaE1a75cF7Aa14183483b8397);
    
    function setUp() public {}

    function run() public {
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
    }
}

interface Governance {
     /** 
      @notice Sets the fee of the TerminalV1.
      @param _terminalV1 The terminalV1 to change the fee of.
      @param _fee The new fee.
    */
    function setFee(ITerminalV1 _terminalV1, uint256 _fee) external;
}