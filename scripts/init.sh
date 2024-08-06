#!/usr/bin/env bash

set -oe pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"


setup () {
  $DIR/setup.sh

  echo "Cleaning up from previous runs..."
  docker compose down --volumes

  echo
  echo "Starting the stack..."
  docker compose up --build -d
}

bitcoind() {
  $DIR/../bin/bitcoin-cli $@
}

litd1-lncli() {
  $DIR/../bin/lncli litd1 $@
}

litd1-tapcli() {
  $DIR/../bin/tapcli litd1 $@
}

litd2-lncli() {
  $DIR/../bin/lncli litd2 $@
}

litd2-tapcli() {
  $DIR/../bin/tapcli litd2 $@
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
  LITD1_ADDRESS=$(litd1-lncli newaddress p2wkh | jq -r .address)
  echo LITD1_ADDRESS: $LITD1_ADDRESS

  LITD2_ADDRESS=$(litd2-lncli newaddress p2wkh | jq -r .address)
  echo LITD2_ADDRESS: $LITD2_ADDRESS
}

getNodeInfo() {
  LITD1_NODE_INFO=$(litd1-lncli getinfo)
  LITD1_NODE_URI=$(echo ${LITD1_NODE_INFO} | jq -r .uris[0])
  LITD1_PUBKEY=$(echo ${LITD1_NODE_INFO} | jq -r .identity_pubkey)
  echo LITD1_PUBKEY: $LITD1_PUBKEY
  echo LITD1_NODE_URI: $LITD1_NODE_URI

  LITD2_NODE_INFO=$(litd2-lncli getinfo)
  LITD2_NODE_URI=$(echo ${LITD2_NODE_INFO} | jq -r .uris[0])
  LITD2_PUBKEY=$(echo ${LITD2_NODE_INFO} | jq -r .identity_pubkey)
  echo LITD2_PUBKEY: $LITD2_PUBKEY
  echo LITD2_NODE_URI: $LITD2_NODE_URI
}

sendFundingTransaction() {
  echo creating raw tx...
  local addresses=($LITD1_ADDRESS $LITD2_ADDRESS)
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
  sendFundingTransaction
  sendFundingTransaction

  # Generate some blocks to confirm the transactions.
  mineBlocks $BITCOIN_ADDRESS 10
}

mintAssets() {
  echo "Minting assets..."
  litd1-tapcli assets mint --type normal --name strike-usdt --supply 100000000 --decimal_display 2 --meta_bytes '{"issuer":"strike"}' --meta_type json --new_grouped_asset
  litd1-tapcli assets mint finalize

  # Get the tweaked group id so that we can mint assitional assets
  TWEAKED_GROUP_KEY=$(litd1-tapcli assets list --show_unconfirmed_mints | jq -r '.assets[] | select(.asset_genesis.name == "strike-usdt") | .asset_group.tweaked_group_key')
  ASSET_ID=$(litd1-tapcli assets list --show_unconfirmed_mints | jq -r '.assets[] | select(.asset_genesis.name == "strike-usdt") | .asset_genesis.asset_id')
  
  echo TWEAKED_GROUP_KEY: $TWEAKED_GROUP_KEY
  echo ASSET_ID: $ASSET_ID

  echo
  echo "Minting additional assets..."
  litd1-tapcli assets mint --type normal --name strike-usdt --supply 100000000 --decimal_display 2 --meta_bytes '{"issuer":"strike"}' --meta_type json --grouped_asset --group_key ${TWEAKED_GROUP_KEY}
  litd1-tapcli assets mint finalize
}

openChannel() {
  # Open a channel between litd2 and litd1.
  echo "Opening channel between litd2 and litd1"
  waitFor litd2-lncli connect $LITD1_NODE_URI
  waitFor litd2-lncli openchannel $LITD1_PUBKEY 10000000

  # Generate some blocks to confirm the channel.
  mineBlocks $BITCOIN_ADDRESS 10
}

waitBitcoind() {
  waitFor bitcoind getnetworkinfo
}

waitForNodes() {
  waitFor litd1-lncli getinfo
  waitFor litd2-lncli getinfo
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

  print_section "OPEN CHANNELS"
  openChannel
}

main
