# Andromeda Payment Conduit

This adapter acts as the `mate` and `operator` of the output conduit of the MIP21 RWA toolkit contracts. It controls the `gem` and sends this to a fixed `withdrawal` address, that is controlled by the `ward`s.

It ties the bookkeeping of withdrawals and repayments to a Centrifuge pool. For this, it mints a custom `Deposit ERC20`, that represents the amount of `gem` locked in the adapter. This ensures that `gem` (e.g. USDC) never leaves the adapter, except to either
* The `withdrawal` address
* One of the `InputConduit`s for repayments

## Withdrawal flow
To draw down new funds, DAI is swapped to `gem`, pushed to the adapter, and `Deposit ERC20` tokens are minted and transferred to the Centrifuge pool. Once the tokenization of the new assets is finished, the `Deposit ERC20` is burned and `gem` is transferred to the withdrawal address.

![Withdrawals](./assets/withdrawals.png)

## Repayment flow
![Repaymens](./assets/repayments.png)

## Emergency flows
![Emergency](./assets/fail-safes.png)

## License
This codebase is licensed under [GNU Lesser General Public License v3.0](https://github.com/centrifuge/liquidity-pools/blob/main/LICENSE).
