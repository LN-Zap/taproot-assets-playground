#!/usr/bin/env bash

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
litd1-litcli() {
  $DIR/../bin/litcli litd1 $@
}

litd2-lncli() {
  $DIR/../bin/lncli litd2 $@
}
litd2-tapcli() {
  $DIR/../bin/tapcli litd2 $@
}
litd2-litcli() {
  $DIR/../bin/litcli litd2 $@
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

# Helper function to print variable names in bold
print_bold_var() {
  local var_name=$1
  local var_value=$2
  echo -e "\033[1m${var_name}:\033[0m ${var_value}"
}

# Helper function to format command with a bold white prompt
format_command() {
  local command=$1
  echo -e "$(colored_bold 37 "$command")\n"
}

# Helper function to print the command
print_command() {
  local command=$1
  colored_bold 33 "COMMAND:"
  format_command "$command"
}

# Helper function to print a section header
print_section() {
  echo -e "\033[1;34m\n==================== $1 ====================\033[0m"
}

# --------------------

intro() {
  colored_bold 34 "Welcome to the Taproot Assets Playground demo!"
  bold "---------------------------------------------"
  echo -e "In this demo, we will...\n"
  echo -e "1. Mint the new L-USDT taproot asset."
  echo -e "2. Verify the minted asset."
  echo -e "3. Demonstrate asset transfer."
  echo
}

getNodeInfo() {
  echo -e "Getting node info...\n"

  LITD1_NODE_INFO=$(litd1-lncli getinfo)
  LITD1_NODE_URI=$(echo ${LITD1_NODE_INFO} | jq -r .uris[0])
  LITD1_PUBKEY=$(echo ${LITD1_NODE_INFO} | jq -r .identity_pubkey)
  print_bold_var "LITD1_PUBKEY" $LITD1_PUBKEY
  print_bold_var "LITD1_NODE_URI" $LITD1_NODE_URI
  echo

  LITD2_NODE_INFO=$(litd2-lncli getinfo)
  LITD2_NODE_URI=$(echo ${LITD2_NODE_INFO} | jq -r .uris[0])
  LITD2_PUBKEY=$(echo ${LITD2_NODE_INFO} | jq -r .identity_pubkey)
  print_bold_var "LITD2_PUBKEY" $LITD2_PUBKEY
  print_bold_var "LITD2_NODE_URI" $LITD2_NODE_URI
  echo
}

mintAsset() {
  print_section "MINT ASSETS"
  echo -e "Mint a new L-USDT taproot asset.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will mint a new L-USDT taproot asset with a supply of 10,000,000,000 units, a decimal display of 4, and metadata indicating the issuer is 'strike'.\n"

  # Define the command to mint a new L-USDT taproot asset
  local command='litd1-tapcli assets mint --type normal --name L-USDT --supply 1000000000 --decimal_display 4 --meta_type json --new_grouped_asset'

  print_command "$command"

  # Prompt the user to continue and execute the command
  prompt_user
  eval $command
}

mintAssetFinalise() {
  print_section "FINALISE ASSET MINT"
  echo -e "Finalise the mint transaction.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will execute the batch and publish your mint transaction to the blockchain.\n"

  # Define the command to finalise the mint transaction
  local command='litd1-tapcli assets mint finalize'

  print_command "$command"

  # Prompt the user to continue and execute the command
  prompt_user
  eval $command
}

getAssetInfo() {
  echo -e "Getting asset info...\n"

  # Get the tweaked group id so that we can mint additional assets
  TWEAKED_GROUP_KEY=$(litd1-tapcli assets list --show_unconfirmed_mints | jq -r 'first(.assets[] | select(.asset_genesis.name == "L-USDT")) | .asset_group.tweaked_group_key')
  ASSET_ID=$(litd1-tapcli assets list --show_unconfirmed_mints | jq -r 'first(.assets[] | select(.asset_genesis.name == "L-USDT")) | .asset_genesis.asset_id')

  print_bold_var "TWEAKED_GROUP_KEY" $TWEAKED_GROUP_KEY
  print_bold_var "ASSET_ID" $ASSET_ID
  echo
}

openChannelBTC() {
  print_section "OPEN CHANNEL (BTC)"
  echo -e "Open a channel between litd2 and litd1.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will open a normal BTC channel from litd2 to litd1 with a capacity of 10,000,000 sats.\n"

  # Define the command to open a normal BTC channel
  local command="litd2-lncli connect \$LITD1_NODE_URI ; litd2-lncli openchannel \$LITD1_PUBKEY 10000000"

  print_command "$command"

  # Prompt the user to continue and execute the command
  prompt_user
  eval $command
}

openChannelAsset() {
  print_section "OPEN CHANNEL (L_USDT)"
  echo -e "Open a channel between litd1 and litd2.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will open an L-USDT Taproot Assets channel from litd1 to litd2 with a capacity of $1,000.\n"

  # Define the command to open an L-USDT Taproot Assets channel
  local command="litd1-litcli ln fundchannel --node_key \${LITD2_PUBKEY} --asset_amount 1000000 --asset_id \${ASSET_ID} --sat_per_vbyte 16"

  print_command "$command"

  # Prompt the user to continue and execute the command
  prompt_user
  eval $command
}

generateInvoice() {
  print_section "GENERATE INVOICE"
  echo -e "Generate an invoice on litd2 for a taproot asset transfer.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will generate an invoice for a taproot asset transfer of 21 units with a memo 'my first taproot asset transfer'.\n"

  # Command to add an invoice
  local command="litd2-litcli ln addinvoice --memo \"my first taproot asset transfer\" --asset_id \${ASSET_ID} --asset_amount 21"

  print_command "$command"

  # Prompt the user to continue and execute the command
  prompt_user
  output=$(eval $command)

  # Extract the payment_request from the output
  INVOICE=$(echo "$output" | sed -n '/{/,/}/p' | jq -r '.payment_request')

  # Print the INVOICE variable in bold
  print_bold_var "INVOICE" "$INVOICE"
}

payInvoice() {
  print_section "PAY INVOICE"
  echo -e "Pay the invoice on litd1 for a taproot asset transfer.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will pay the invoice generated on litd2 for a taproot asset transfer of 21 units.\n"

  local command="litd1-litcli ln payinvoice --pay_req \${INVOICE} --asset_id \${ASSET_ID} --force"

  print_command "$command"

  # Prompt the user to continue and execute the command
  prompt_user
  eval $command
}

mineBlocks() {
  BLOCKS=6
  PROPAGATION_TIME=6

  print_section "MINE BLOCKS"
  echo -e "Mine 6 blocks.\n"

  colored_bold 32 "EXPLANATION:"
  echo -e "This command will mine 6 blocks to fully confirm any pending transactions.\n"

  # Construct the command string with escaped variables
  local command="new_address=\$(bitcoind getnewaddress) && bitcoind generatetoaddress ${BLOCKS} \${new_address}"

  print_command "$command"

  # Prompt the user to continue
  prompt_user
  eval $command

  echo -e "Waiting ${PROPAGATION_TIME} seconds for blocks to propagate...\n"
  sleep ${PROPAGATION_TIME}
}

main() {
  intro

  getNodeInfo

  mintAsset
  mintAssetFinalise
  getAssetInfo

  mineBlocks

  openChannelBTC
  mineBlocks

  openChannelAsset
  mineBlocks

  generateInvoice
  payInvoice
}

main
