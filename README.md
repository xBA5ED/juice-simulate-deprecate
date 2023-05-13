# Simulation of Juicebox V1 and V2 deprecation txs
Runs the transactions that deprecate V1 (, V1_1) and V2 Juicebox.

## Requirements
- Forge
- Tenderly CLI (installed and logged in)
- Yarn

## Usage

Install all dependicies by running the following command:
```
git submodule update --init --recursive && yarn
```

Modify the ENV vars in `tenderly_devnet.sh`.

Run 
```
bash tenderly_devnet.sh
```

Go to Tenderly devnets and check all the transactions/explore the new state.
