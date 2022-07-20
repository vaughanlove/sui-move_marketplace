# sui cli calls for the current program.

### publish
sui client publish --path . --gas-budget 10000
### create_market
sui client call --function create_market --module marketplace --package $PACKAGE_ID --gas-budget 5000
### create (initiates an escrow - maybe should change name.)
sui client call --function create --module marketplace --package $PACKAGE_ID --args $MARKETPLACE $PRICE $TEST_NFT --type-args 0x2::devnet_nft::DevNetNFT 0x2::sui::SUI --gas-budget 10000
### exchange 
sui client call --function exchange --module marketplace --package $PACKAGE_ID --args $PAID $LISTING --type-args 0x2::devnet_nft::DevNetNFT 0x2::sui::SUI --gas-budget 10000
### cancel
sui client call --function cancel --module marketplace --package $PACKAGE_ID --args $MARKETPLACE $LISTING --type-args 0x2::devnet_nft::DevNetNFT 0x2::sui::SUI --gas-budget 10000