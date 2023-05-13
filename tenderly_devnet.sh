LOCAL_SIMULATION_RPC_URL=
TENDERLY_PROJECT=project
TENDERLY_DEV_NET_TEMPLATE=jb-simulate-deprecate

# Exit when any command fails
set -e

# We can't simulate in both foundry and tenderly, so we simulate with foundry first, then push the txs to the the tenderly devnet
forge script --rpc-url=$LOCAL_SIMULATION_RPC_URL ./script/DeprecateSimulateScript.sol:DeprecateSimulateScript --unlocked --sender 0x0Bc1b73d735083Adb4f26671BC90B68a86B33dE4 

# Create a new tenderly devnet
RPC_URL=$(tenderly devnet spawn-rpc --template $TENDERLY_DEV_NET_TEMPLATE --project $TENDERLY_PROJECT 2>&1)

# Push the txs to the tenderly devnet
forge script --rpc-url=$RPC_URL ./script/DeprecateSimulateScript.sol:DeprecateSimulateScript --unlocked --sender 0x0Bc1b73d735083Adb4f26671BC90B68a86B33dE4 --broadcast --resume
 