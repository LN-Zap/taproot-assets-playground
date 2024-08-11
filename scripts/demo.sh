#!/usr/bin/env bash

set -oe pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --non-interactive    Run the script in non-interactive mode"
  echo "  --help               Display this help message and exit"
  exit 0
}

NON_INTERACTIVE=false
for arg in "$@"; do
  case $arg in
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      echo "Error: Unknown option '$arg'"
      show_help
      exit 1
      ;;
  esac
done

prompt_user() {
  if [ "$NON_INTERACTIVE" = true ]; then
    echo "Running in non-interactive mode. Continuing..."
  else
    read -p "Press 'Y' to continue or any other key to exit [Y/n]: " choice
    choice=${choice:-Y}
    if [[ "${choice,,}" != "y" ]]; then
      echo "Exiting..."
      exit 1
    fi
    echo "Continuing with the script..."
  fi
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

# Helper function to output text in bold
bold() {
  echo -e "\033[1m$1\033[0m"
}

# Helper function to output text in bold and a specific color
colored_bold() {
  local color_code=$1
  shift
  echo -e "\033[1;${color_code}m$@\033[0m"
}

# Helper function to format command with a bold white prompt
format_command() {
  local command=$1
  echo -e "\033[1;37m$ \033[0m$command\n"
}

# Helper function to print a section header
print_section() {
  echo -e "\033[1;34m\n==================== $1 ====================\033[0m"
}

# --------------------

intro() {
  colored_bold 34 "Welcome to the Taproot Assets Playground demo!"
  bold "---------------------------------------------"
  echo -e "In this demo, we will mint a new L-USDT taproot asset with a supply of 10,000,000,000 units, a decimal display of 4, and metadata indicating the issuer is 'strike'.\n"
}

getNodeInfo() {
  echo "Getting node info..."

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

  echo -e "\n---\n"
}

mintAsset() {
  print_section "MINT ASSETS"
  echo -e "Mint a new L-USDT taproot asset.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will mint a new L-USDT taproot asset with a supply of 10,000,000,000 units, a decimal display of 4, and metadata indicating the issuer is 'strike'.\n"

  # Define the command to mint a new L-USDT taproot asset
  local command='litd1-tapcli assets mint --type normal --name L-USDT --supply 10_000_000_000 --decimal_display 4 --meta_type json --new_grouped_asset'

  colored_bold 33 "COMMAND:"
  format_command "$command"

  # Prompt the user to continue
  prompt_user
  eval $command
}

mintAssetFinalise() {
  print_section "FINALISE ASSET MINT"
  echo -e "Finalise the mint transaction.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will execute the batch and publish your mint transaction to the blockchain.\n"

  # Define the command to mint a new L-USDT taproot asset
  local command='litd1-tapcli assets mint finalize'

  colored_bold 33 "COMMAND:"
  format_command "$command"

  # Prompt the user to continue
  prompt_user
  eval $command

  # Get the tweaked group id so that we can mint additional assets
  TWEAKED_GROUP_KEY=$(litd1-tapcli assets list --show_unconfirmed_mints | jq -r '.assets[] | select(.asset_genesis.name == "L-USDT") | .asset_group.tweaked_group_key')
  ASSET_ID=$(litd1-tapcli assets list --show_unconfirmed_mints | jq -r '.assets[] | select(.asset_genesis.name == "L-USDT") | .asset_genesis.asset_id')

  echo "TWEAKED_GROUP_KEY: $TWEAKED_GROUP_KEY"
  echo "ASSET_ID: $ASSET_ID"
}


openChannel() {
  print_section "OPEN CHANNEL"
  echo -e "Open a channel between litd2 and litd1.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will open a normal BTC channel from litd2 to litd1 with a capacity of 10,000,000 sats.\n"

  # Construct the command string with escaped variables
  local command="waitFor litd2-lncli connect \$LITD1_NODE_URI && waitFor litd2-lncli openchannel \$LITD1_PUBKEY 10000000"

  colored_bold 33 "COMMAND:"
  format_command "$command"

  # Prompt the user to continue
  prompt_user
  eval $command
}

mineBlocks() {
  print_section "MINE BLOCKS"
  echo -e "Mine 3 blocks.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will mine 3 blocks to fully confirm any pending transactions.\n"

  # Construct the command string with escaped variables
  local command="new_address=\$(bitcoind getnewaddress) && bitcoind generatetoaddress 3 \${new_address}"

  colored_bold 33 "COMMAND:"
  format_command "$command"

  # Prompt the user to continue
  prompt_user
  eval $command
}

main() {
  intro
  getNodeInfo
  mintAsset
  mintAssetFinalise
  mineBlocks
  openChannel
  mineBlocks
}

main
