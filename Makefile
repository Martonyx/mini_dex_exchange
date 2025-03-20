-include .env

build:; forge build

deploy-usyt:
	forge script script/deployUSYT.s.sol:DeployUSYT --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-SimpleToken : 
	forge script script/deploySimpleToken.s.sol:DeploySimpleCoin --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

verifyContract :
	forge verify-contract --chain-id 11155111 --watch \
	 0x61F4BE9902408787a96B3Ca3f9cC0c89eb02E871 \
	  Pair \
	--etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

verifyContractWithArgs :
	forge verify-contract --chain-id 11155111 --watch \
	0x2eB60c8ecDB507c0B79059Ee8DcDfeeBcc369B8c \
	Pair \
	--constructor-args 0x0000000000000000000000009f1a0317be662e848668278688ffc013b9c26f0e000000000000000000000000ad2caf956e995f331c7c3a948ee6d618dc0d54d10000000000000000000000005212ecce193c932a20a549915821240e8083478400000000000000000000000086293364a4a2a3929c93d9bca1be623c0d00eb2f \
	--etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-dexFactory :
	forge script script/deployDexFac.s.sol:DeployFactory --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv


deploy-dexRouter :
	forge script script/deployDexRouter.s.sol:DeployRouter --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-SimpleToken1 : 
	forge script script/deploySimpleToken1.s.sol:DeploySimpleCoin1 --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv


deploy-mockusdc : 
	forge script script/deployMockUSDC.s.sol:DeployUSDC --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

deploy-usytconverter : 
	forge script script/deployConverter.s.sol:DeployConverter --rpc-url $(SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
