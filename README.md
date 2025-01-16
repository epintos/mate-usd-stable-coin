## MATE 🧉 Stablecoin 💵

<img src="./mate-stable-coin-img.png" alt="MATE Stablecoin" width="200"/>

Developed a smart contract to implement a stable coin with the following characteristics:
- Anchored to USD 💵 (and not Argentine peso 🧉)
- Algorithmic.
- Collateral: wETH and wBTC.

This practice project allows me to explore and experiment with various Solidity concepts learned through [Updraft Cyfrin](https://updraft.cyfrin.io/courses).

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

Mint:
```shell
$ make mint-nft CHARACTER_INDEX=0
```

Attack:
```shell
$ make attack TOKEN_ID=0
```
