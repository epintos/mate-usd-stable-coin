## Defi Stablecoin

Developed a smart contract to implement a stable coin with the following characteristics:
- Anchored to USD.
- Algorithmic.
- Collaborateral: wETH and wBTC.

This is a practice project where I explore and experiment with various Solidity concepts learned in [Updraft Cyfrin](https://updraft.cyfrin.io/courses).

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
