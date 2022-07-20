import { JsonRpcProvider } from '@mysten/sui.js';

//localnet_rpc = "http://127.0.0.1:5001";
//devnet_rpc = "https://gateway.devnet.sui.io:443";

const provider = new JsonRpcProvider('http://127.0.0.1:5001');

const objects = await provider.getObject(
  '0x89ef177c616709c69fcd3e380e3bdb90f8e44252'
);

console.log(objects.details.data)

//{"jsonrpc":"2.0", "id": 1, "method": "sui_subscribeEvent", "params": [{"All":[{"EventType":"MoveEvent"}, {"Package":"0x2"}, {"Module":"devnet_nft"}]}}