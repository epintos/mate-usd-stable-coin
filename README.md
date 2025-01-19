## MATE 🧉 Stablecoin 💵

<img src="./mate-stable-coin-img.png" alt="MATE Stablecoin" width="200"/>

Note: This project is a practice exercise designed to explore and experiment with various Solidity concepts learned through the [Updraft Cyfrin](https://updraft.cyfrin.io/courses).

Developed a smart contract to implement a stable coin with the following characteristics:
- Anchored to USD 💵 (and not Argentine peso 🧉).
- Algorithmic.
- Collateral: wETH and wBTC.
- Users need to be 200% overcollateralized.
- Liquidators get 10% bonus.
- Known issues: 
   - If collateral/USD prices drops quickly, engine wouldn't be able to pay liquidators and system breaks.
   - If Chainlink network is down, the system is unusable.

## Usage

### Install

```shell
$ make install
```

### Test

```shell
$ make test
```

### Deploy

```shell
$ make deploy-anvil
```

```shell
$ make deploy-sepolia
```

### Fund metamask or others

```shell
$ make fund-account
```

### Interactions
