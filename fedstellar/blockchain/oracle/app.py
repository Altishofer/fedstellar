import os
import json
import time

import requests
from solcx import compile_standard, install_solc
from web3 import Web3
from eth_account import Account
from flask import Flask, jsonify, request
from web3.middleware import construct_sign_and_send_raw_middleware
from web3.middleware import geth_poa_middleware

app = Flask(__name__)


class Manager:

	def __init__(self):
		self.contract_abi = dict()
		self.ready = self.wait_until_rpc_up()
		self.acc = self.unlock()
		self.web3 = self.initialize_geth()
		self.contractObj = self.compile_contract()
		self.contractAddress = self.deploy()

	def wait_until_rpc_up(self):
		headers = {
			'Content-type': 'application/json',
			'Accept': 'application/json'
		}

		data = {
			'jsonrpc': '2.0',
			'method': 'eth_accounts',
			'id': 1,
			'params': []
		}
		url = "http://172.25.0.104:8545"
		for _ in range(6):
			try:
				r = requests.post(
					url=url,
					json=data,
					headers=headers
				)
				if r.status_code == 200:
					print(f"SUCCESS: RPC node up and running")
					return True
			except Exception as e:
				print("WARNING: RPC-Server not ready - sleep 10")
				time.sleep(10)
		return False

	def initialize_geth(self):
		node_url = "http://172.25.0.104:8545"
		web3 = Web3(Web3.HTTPProvider(node_url))
		web3.middleware_onion.inject(geth_poa_middleware, layer=0)
		web3.middleware_onion.add(construct_sign_and_send_raw_middleware(self.acc))
		web3.eth.default_account = self.acc.address
		print(f"SUCCESS: Account created at {self.acc.address}")
		return web3

	def compile_contract(self):
		with open("faucet.sol", "r") as file:
			simple_storage_file = file.read()
		install_solc("0.8.22")
		compiled_sol = compile_standard(
			{
				"language": "Solidity",
				"sources": {"faucet.sol": {"content": simple_storage_file}},
				"settings": {
					"evmVersion": 'paris',
					"outputSelection": {
						"*": {
							"*": ["abi", "metadata", "evm.bytecode", "evm.sourceMap"]
						}
					}
				},
			},
			solc_version="0.8.22",
		)
		with open("compiled_code.json", "w") as file:
			json.dump(compiled_sol, file)
		contract_bytecode = compiled_sol["contracts"]["faucet.sol"]["Faucet"]["evm"]["bytecode"]["object"]
		self.contract_abi = json.loads(compiled_sol["contracts"]["faucet.sol"]["Faucet"]["metadata"])["output"]["abi"]
		print(f"SUCCESS: Solidity files compiled and bytecode ready")
		return self.web3.eth.contract(abi=self.contract_abi, bytecode=contract_bytecode)

	def unlock(self):
		private_key = os.environ.get("PRIVATE_KEY")
		return Account.from_key("0x" + private_key)

	def send_eth(self, address):
		for _ in range(3):
			try:
				tx = {
					"chainId": self.web3.eth.chain_id,
					"from": self.acc.address,
					"value": self.web3.to_wei("500", "ether"),
					"to": self.web3.to_checksum_address(address),
					"nonce": self.web3.eth.get_transaction_count(self.acc.address),
					"gasPrice": self.web3.to_wei("1", "gwei"),
					"gas": self.web3.to_wei("22000", "wei")
				}
				tx_receipt = self.sign_and_deploy(tx)
				time.sleep(4)
				return f"SUCESS: {tx_receipt}"
			except Exception as e:
				print(f"EXCEPTION: send_eth({address}) => {e}")
				time.sleep(2)

	def sign_and_deploy(self, hash):
		s_tx = self.web3.eth.account.sign_transaction(hash, private_key=self.acc.key)
		sent_tx = self.web3.eth.send_raw_transaction(s_tx.rawTransaction)
		return self.web3.eth.wait_for_transaction_receipt(sent_tx, timeout=5)

	def deploy(self):
		# self.contractObj = self.compile_contract()
		for _ in range(20):
			tx_hash = self.contractObj.constructor().build_transaction({
				"chainId": self.web3.eth.chain_id,
				"from": self.acc.address,
				"value": self.web3.to_wei("3", "ether"),
				"gasPrice": self.web3.to_wei("1", "gwei"),
				"nonce": self.web3.eth.get_transaction_count(self.acc.address, 'pending')
			})
			try:
				tx_receipt = self.sign_and_deploy(tx_hash)
				# print(self.web3.to_json(tx_receipt))
				contract_address = tx_receipt["contractAddress"]
				if contract_address:
					print(f"SUCCESS: Contract deployed at {contract_address}")
					return contract_address
				print(f"WARNING: Deployment iteration failed -> {contract_address}")
			except Exception as e:
				print(e)
				time.sleep(5)
		return print("ERROR: Deployment failed")

	def test_write(self, word: str):
		unsigned_trx = self.contractObj.functions.writeStore(word).build_transaction(
			{
				"chainId": self.web3.eth.chain_id,
				"from": self.acc.address,
				"nonce": self.web3.eth.get_transaction_count(self.acc.address),
				"gasPrice": self.web3.to_wei("1", "gwei")
			}
		)
		conf = self.sign_and_deploy(unsigned_trx)
		return self.web3.to_json(conf)

	def test_read(self):
		self.contractObj = self.web3.eth.contract(
			abi=self.contractObj.abi,
			bytecode=self.contractObj.bytecode,
			address=self.contractAddress
		)

		number = self.contractObj.functions.getStore().call({
			"from": self.acc.address,
			"gasPrice": self.web3.to_wei("1", "gwei")
		})
		return number

	def create_account(self):
		acc = Account.create()
		self.send_eth(acc.address)
		return {
			"address": acc.address,
			"pk": acc.key.hex()
		}

	def get_balance(self, addr):
		cAddr = self.web3.to_checksum_address(addr)
		balance = self.web3.eth.get_balance(cAddr, "latest")
		return {
			"address": cAddr,
			"balance_eth": self.web3.from_wei(balance, "ether")
		}

@app.route("/")
def home():
	return jsonify({
		"Message": "Oracle up and running"
	})


@app.route("/faucet", methods=["POST"])
def faucet():
	address = request.get_json().get("address")
	return jsonify({
		"Message": m.send_eth(address)
	})


@app.route("/testWrite", methods=["POST"])
def testNumberWrite():
	number = request.get_json().get("numberToStore")
	return jsonify({
		"Message": m.test_write(number)
	})


@app.route("/testRead", methods=["GET"])
def testNumberRead():
	return jsonify({
		"Message": m.test_read()
	})


@app.route("/createAccount", methods=["GET"])
def createAccount():
	return jsonify(m.create_account())


@app.route("/getBalance", methods=["GET"])
def getBalance():
	addr = request.get_json().get("address")
	return jsonify(m.get_balance(addr))


@app.route("/deploy", methods=["GET"])
def deployContract():
	if m.contractAddress:
		return jsonify(
			{
				"message": "SUCCESS",
				"address": m.contractAddress,
				"abi": m.contract_abi
			})
	m.deploy()
	return jsonify(
		{
			"message": "SUCCESS" if m.contractAddress else "ERROR",
			"address": m.contractAddress,
			"abi": m.contract_abi
		})

@app.route("/status", methods=["GET"])
def ready():
	if not m.ready:
		return {'message': 'Blockchain does not respond, wait 10'}, 503, {'Content-Type': 'application/json'}
	else:
		return {'message': 'Blockchain responded'}, 200, {'Content-Type': 'application/json'}

@app.route("/getContract", methods=["GET"])
def contract():
	return jsonify({
		"address": m.contractAddress,
		"abi": m.contract_abi
	})


if __name__ == "__main__":
	m = Manager()
	app.run(debug=False, host="0.0.0.0", port=8081)
