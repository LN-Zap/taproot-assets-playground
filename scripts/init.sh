#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


setup () {
  $DIR/setup.sh

  echo "Cleaning up from previous runs..."
  docker compose down --volumes

  echo
  echo "Starting the stack..."
  docker compose up -d
}

bitcoind() {
  $DIR/../bin/bitcoin-cli $@
}

lncli() {
  $DIR/../bin/lncli $@
}

tapcli() {
  $DIR/../bin/tapcli $@
}

waitFor() {
  counter=0
  until $@ || [ $counter -eq 60 ]; do
    >&2 echo "$@ unavailable - waiting..."
    sleep 1
    ((counter++))
  done

  if [ $counter -eq 60 ]; then
    >&2 echo "Waited for 60 seconds, but $@ is still unavailable. Exiting."
    exit 1
  fi
}

print_section() {
  echo -e "\033[1;34m\n==================== $1 ====================\033[0m"
}

createBitcoindWallet() {
  $DIR/../bin/bitcoin-cli createwallet default || $DIR/../bin/bitcoin-cli loadwallet default || true
}

mineBlocks() {
  ADDRESS=$1
  AMOUNT=${2:-1}
  echo Mining $AMOUNT blocks to $ADDRESS...
  bitcoind generatetoaddress $AMOUNT $ADDRESS
  sleep 0.5 # waiting for blocks to be propagated
}

initBitcoinChain() {
  # Mine 103 blocks to initliase a bitcoind node.
  mineBlocks $BITCOIN_ADDRESS 103
}

generateBitcoinAddress() {
  BITCOIN_ADDRESS=$(bitcoind getnewaddress)
  echo BITCOIN_ADDRESS: $BITCOIN_ADDRESS
}

generateNodeAddresses() {
  LITD_ADDRESS=$(lncli newaddress p2wkh | jq -r .address)
  echo LITD_ADDRESS: $LITD_ADDRESS
}

getNodeInfo() {
  LITD_NODE_INFO=$(lncli getinfo)
  LITD_NODE_URI=$(echo ${LITD_NODE_INFO} | jq -r .uris[0])
  LITD_PUBKEY=$(echo ${LITD_NODE_INFO} | jq -r .identity_pubkey)
  echo LITD_PUBKEY: $LITD_PUBKEY
  echo LITD_NODE_URI: $LITD_NODE_URI
}

sendFundingTransaction() {
  echo creating raw tx...
  local addresses=($LITD_ADDRESS)
  local outputs=$(jq -nc --arg amount 1 '$ARGS.positional | reduce .[] as $address ({}; . + {($address) : ($amount | tonumber)})' --args "${addresses[@]}")
  RAW_TX=$(bitcoind createrawtransaction "[]" $outputs)
  echo RAW_TX: $RAW_TX

  echo funding raw tx $RAW_TX...
  FUNDED_RAW_TX=$(bitcoind fundrawtransaction "$RAW_TX" | jq -r .hex)
  echo FUNDED_RAW_TX: $FUNDED_RAW_TX

  echo signing funded tx $FUNDED_RAW_TX...
  SIGNED_TX_HEX=$(bitcoind signrawtransactionwithwallet "$FUNDED_RAW_TX" | jq -r .hex)
  echo SIGNED_TX_HEX: $SIGNED_TX_HEX

  echo sending signed tx $SIGNED_TX_HEX...
  bitcoind sendrawtransaction "$SIGNED_TX_HEX"
}

fundNodes() {
  # Fund with multiple transactions to that we have multiple utxos to spend on each of the lnd nodes.
  sendFundingTransaction
  sendFundingTransaction
  sendFundingTransaction

  # Generate some blocks to confirm the transactions.
  mineBlocks $BITCOIN_ADDRESS 10
}

mintAssets() {
  echo "Minting assets..."
  tapcli assets mint --type normal --name strike-usdt --supply 100000000 --decimal_display 2 --meta_bytes '{"issuer":"strike"}' --meta_type json --new_grouped_asset
  tapcli assets mint finalize

  # Get the tweaked group id so that we can mint assitional assets
  TWEAKED_GROUP_KEY=$(tapcli assets list --show_unconfirmed_mints | jq -r '.assets[] | select(.asset_genesis.name == "strike-usdt") | .asset_group.tweaked_group_key')
  ASSET_ID=$(tapcli assets list --show_unconfirmed_mints | jq -r '.assets[] | select(.asset_genesis.name == "strike-usdt") | .asset_genesis.asset_id')
  
  echo TWEAKED_GROUP_KEY: $TWEAKED_GROUP_KEY
  echo ASSET_ID: $ASSET_ID

  echo
  echo "Minting additional assets..."
  tapcli assets mint --type normal --name strike-usdt --supply 100000000 --decimal_display 2 --meta_bytes '{"issuer":"strike"}' --meta_type json --grouped_asset --group_key ${TWEAKED_GROUP_KEY}
  tapcli assets mint finalize
}

waitBitcoind() {
  waitFor bitcoind getnetworkinfo
}

waitForNodes() {
  waitFor lncli getinfo
}

main() {
  print_section "SETUP"
  setup

  print_section "WAIT FOR BITCOIND"
  waitBitcoind

  print_section "CREATE BITCOIND WALLET"
  createBitcoindWallet

  print_section "GENERATE BITCOIN ADDRESS"
  generateBitcoinAddress

  print_section "INITIALIZE BITCOIN CHAIN"
  initBitcoinChain

  print_section "WAIT FOR NODES"
  waitForNodes

  print_section "GENERATE NODE ADDRESSES"
  generateNodeAddresses

  print_section "GET NODE INFO"
  getNodeInfo

  print_section "FUND NODES"
  fundNodes

  print_section "MINT ASSERS"
  mintAssets
}

main
