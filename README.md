# Simulation of Juicebox V1 and V2 deprecation txs

Simulate the transactions to deprecate JuiceboxDAO's V1(V1_1) and V2 projects as described in [JBP-384](https://www.jbdao.org/p/384).

## Requirements

- [Forge](https://book.getfoundry.sh/getting-started/installation.html)
- [Tenderly CLI](https://github.com/Tenderly/tenderly-cli) (installed and logged in via `tenderly login`)
- yarn

## Usage

1. Install all dependicies by running the following command:

```
git submodule update --init --recursive && yarn
```

2. If you don't already have a Tenderly project, create one at [dashboard.tenderly.co](https://dashboard.tenderly.co/).
3. Navigate to the "DevNets" section of the Tenderly dashboard and click "Create Template".
4. Select "Mainnet" and name your template "jb-simulate-deprecate". Leave the advanced settings as they are.
5. Modify the ENV vars in `tenderly_devnet.sh`. `LOCAL_SIMULATION_RPC_URL` can be any mainnet JSON-RPC endpoint, `TENDERLY_PROJECT` should be the name of your Tenderly project from step 2, and `TENDERLY_DEV_NET_TEMPLATE` should be the name of your template from step 4.
6. Run:

```bash
bash tenderly_devnet.sh
```

Once the script completes, open `jb-simulate-deprecate` in the DevNets section of your Tenderly dashboard. You should be able to find the simulations under "All Runs".

Go to Tenderly devnets and check all the transactions/explore the new state.
