#
# This file an adaptation and extension of the p2pfl library (https://pypi.org/project/p2pfl/).
# Refer to the LICENSE file for licensing information.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#


import logging
import time

import requests
import torch
from torch import nn

from eth_account import Account
from web3 import Web3
from web3.middleware import construct_sign_and_send_raw_middleware
from web3.middleware import geth_poa_middleware

from fedstellar.learning.aggregators.aggregator import Aggregator
from fedstellar.learning.aggregators.helper import cosine_metric, euclidean_metric, minkowski_metric, manhattan_metric, pearson_correlation_metric, jaccard_metric


class BlockchainReputation(Aggregator):
    """
	Blockchain Prototype
	"""

    def __init__(self, learner, node_name="unknown", config=None, direct_neighbors=None):
        super().__init__(node_name, config)
        self.config = config
        self.role = self.config.participant["device_args"]["role"]
        logging.info("[BlockchainReputation] My config is {}".format(self.config))
        self.__neighbors = direct_neighbors

        self.__learner = learner
        self.node_name = node_name
        self.__blockchain = Blockchain(self.__neighbors, self.node_name)

    def aggregate(self, model_obj_collection):

        print(f"{'*' * 50} BLOCKCHAIN AGGREGATION: START {'*' * 50}")

        if not len(model_obj_collection):
            logging.error("[BlockchainReputation] Trying to aggregate models when there are no models")
            return None

        current_models = {}
        for subnodes, (submodel, _) in model_obj_collection.items():
            sublist = subnodes.split()
            for node in sublist:
                current_models[node] = submodel

        local_model = self.__learner.get_parameters()
        final_model = {layer: torch.zeros_like(param) for layer, param in local_model.items()}

        neighbor_names = [neighbor_name for neighbor_name in current_models.keys() if neighbor_name != self.node_name]

        for neighbor_name in neighbor_names:
            untrusted_model = current_models[neighbor_name]

            # local_opinion = self.cossim_loss_opinion(neighbor_name, local_model, untrusted_model)
            # local_opinion = self.euclidean_opinion(neighbor_name, local_model, untrusted_model)
            local_opinion = self.minkowski_opinion(neighbor_name, local_model, untrusted_model)
            # local_opinion = self.manhattan_opinion(neighbor_name, local_model, untrusted_model)
            # local_opinion = self.pearson_correlation_opinion(neighbor_name, local_model, untrusted_model)
            # local_opinion = self.jaccard_opinion(neighbor_name, local_model, untrusted_model)

            self.__blockchain.push_opinion(neighbor_name, local_opinion)

        reputation_values = {name: self.__blockchain.get_reputation(name) for name in current_models.keys()}

        normalized_reputation_values = {name: round(reputation_values[name] / sum(reputation_values.values()), 3) for
                                        name in reputation_values}

        print(f"AGGREGATION: Computed reputation for all updates: {reputation_values}", flush=True)
        print(f"AGGREGATION: Normalized reputation for aggregation: {normalized_reputation_values}", flush=True)

        for neighbor_name in neighbor_names:
            neighbor_model = current_models[neighbor_name]
            for layer in final_model:
                final_model[layer] += neighbor_model[layer] * normalized_reputation_values[neighbor_name]  # * n_samples

        print(f"{'*' * 50} BLOCKCHAIN AGGREGATION: FINISHED {'*' * 50}", flush=True)
        return final_model

    def cossim_loss_opinion(self, neighbor_name, local_model, untrusted_model):
        cossim = cosine_metric(local_model, untrusted_model, similarity=True)
        avg_loss = self.__learner.validate_neighbour_model(untrusted_model)
        local_opinion = max(min(int(cossim * (1 - avg_loss) * 100), 100), 1)
        print(
            f"AGGREGATION: neighbor: {neighbor_name}, cossim: {round(cossim, 2)}, avg_loss: {round(avg_loss, 2)}, 1-avg_loss: {round(1 - avg_loss, 2)} trust: {local_opinion}%",
            flush=True
        )
        return local_opinion

    def euclidean_opinion(self, neighbor_name, local_model, untrusted_model):
        metric = euclidean_metric(local_model, untrusted_model)
        local_opinion = max(min(int(metric * 100), 100), 1)
        print(
            f"AGGREGATION: neighbor: {neighbor_name}, euclidean: {round(metric, 2)}, trust: {local_opinion}%",
            flush=True
        )
        return local_opinion

    def minkowski_opinion(self, neighbor_name, local_model, untrusted_model):
        metric = minkowski_metric(local_model, untrusted_model, p=2)
        local_opinion = max(min(int(metric * 100), 100), 1)
        print(
            f"AGGREGATION: neighbor: {neighbor_name}, minkowski: {round(metric, 2)}, trust: {local_opinion}%",
            flush=True
        )
        return local_opinion

    def manhattan_opinion(self, neighbor_name, local_model, untrusted_model):
        metric = manhattan_metric(local_model, untrusted_model)
        local_opinion = max(min(int(metric * 100), 100), 1)
        print(
            f"AGGREGATION: neighbor: {neighbor_name}, manhattan: {round(metric, 2)}, trust: {local_opinion}%",
            flush=True
        )
        return local_opinion

    def pearson_correlation_opinion(self, neighbor_name, local_model, untrusted_model):
        metric = pearson_correlation_metric(local_model, untrusted_model)
        local_opinion = max(min(int(metric * 100), 100), 1)
        print(
            f"AGGREGATION: neighbor: {neighbor_name}, pearson: {round(metric, 2)}, trust: {local_opinion}%",
            flush=True
        )
        return local_opinion

    def jaccard_opinion(self, neighbor_name, local_model, untrusted_model):
        metric = jaccard_metric(local_model, untrusted_model)
        local_opinion = max(min(int(metric * 100), 100), 1)
        print(
            f"AGGREGATION: neighbor: {neighbor_name}, jaccard: {round(metric, 2)}, trust: {local_opinion}%",
            flush=True
        )
        return local_opinion


class Blockchain:

    def __init__(self, neighbors, home_address):
        self.__header = {
            'Content-type': 'application/json',
            'Accept': 'application/json'
        }
        self.__neighbors = neighbors
        self.__home_ip = home_address
        self.__private_key = str()
        self.__acc_address = str()
        self.__rpc_url = "http://172.25.0.104:8545"
        self.__oracle_url = "http://172.25.0.105:8081"
        self.__balance = float()  # DDos protection?

        self.__wait_for_blockchain()
        self.__acc = self.__create_account()
        self.__web3 = self.__initialize_geth()
        self.__contract_obj = self.__get_contract_from_oracle()
        self._register_neighbors()

        # FIXME: remove before pushing to prod
        #self.__testing()

    def __wait_for_blockchain(self):
        for _ in range(20):
            try:
                r = requests.get(
                    url=f"{self.__oracle_url}/status",
                    headers=self.__header,
                    timeout=10
                )
                if r.status_code == 200:
                    print(f"BLOCKCHAIN: wait_for_blockchain() => blockchain up and running", flush=True)
                    return
            except Exception as e:
                print(f"EXCEPTION: wait_for_blockchain => {e}", flush=True)
                time.sleep(3)

    def __initialize_geth(self):
        web3 = Web3(Web3.HTTPProvider(self.__rpc_url))
        web3.middleware_onion.inject(geth_poa_middleware, layer=0)
        web3.middleware_onion.add(construct_sign_and_send_raw_middleware(self.__acc))
        web3.eth.default_account = self.__acc_address
        return web3

    def __get_contract_from_oracle(self):
        for _ in range(3):
            try:
                r = requests.get(
                    url=f"{self.__oracle_url}/getContract",
                    headers=self.__header,
                    timeout=10
                )
                if r.status_code == 200:
                    json_response = r.json()
                    print(f"BLOCKCHAIN: Contract requested from oracle at address {json_response.get('address')}",
                          flush=True)
                    return self.__web3.eth.contract(
                        abi=json_response.get("abi"),
                        address=json_response.get("address")
                    )
            except Exception as e:
                print(f"EXCEPTION: get_contract_from_oracle() => {e}", flush=True)
                time.sleep(2)

    def __create_account(self):
        acc = Account.create()
        web3 = Web3()
        self.__private_key = web3.to_hex(acc.key)
        self.__acc_address = web3.to_checksum_address(acc.address)
        for _ in range(3):
            try:
                r = requests.post(
                    url=f"{self.__oracle_url}/faucet",
                    json={f"address": self.__acc_address},
                    headers=self.__header,
                    timeout=10
                )
                if r.status_code == 200:
                    print(f"BLOCKCHAIN: Funds successfully requested from oracle", flush=True)
                    return acc
            except Exception as e:
                print(f"EXCEPTION: create_account() => {e}", flush=True)
                time.sleep(2)

    def __request_balance(self):
        for _ in range(3):
            try:
                balance = self.__web3.eth.get_balance(self.__acc_address, "latest")
                balance_eth = self.__web3.from_wei(balance, "ether")
                print(f"BLOCKCHAIN: Current balance of node = {balance_eth} ETH", flush=True)
                return {
                    "address": self.__acc_address,
                    "balance_eth": self.__web3.from_wei(balance, "ether")
                }
            except Exception as e:
                print(f"EXCEPTION: request_balance() => {e}", flush=True)
                time.sleep(2)

    def __sign_and_deploy(self, trx_hash):
        s_tx = self.__web3.eth.account.sign_transaction(trx_hash, private_key=self.__private_key)
        sent_tx = self.__web3.eth.send_raw_transaction(s_tx.rawTransaction)
        return self.__web3.eth.wait_for_transaction_receipt(sent_tx)

    def push_opinion(self, ip_address: str, opinion: int):
        for _ in range(3):
            try:
                unsigned_trx = self.__contract_obj.functions.rateNeighbor(ip_address, opinion).build_transaction(
                    {
                        "chainId": self.__web3.eth.chain_id,
                        "from": self.__acc_address,
                        "nonce": self.__web3.eth.get_transaction_count(
                            self.__web3.to_checksum_address(self.__acc_address)
                        ),
                        "gasPrice": self.__web3.to_wei("1", "gwei")
                    }
                )
                conf = self.__sign_and_deploy(unsigned_trx)
                json_response = self.__web3.to_json(conf)
                print(f"BLOCKCHAIN: Rating {ip_address} with {opinion}%", flush=True)
                return json_response
            except Exception as e:
                print(f"EXCEPTION: push_opinion({ip_address}, {opinion}) => {e}", flush=True)
                time.sleep(2)

    def get_reputation(self, ip_address: str) -> int:
        for _ in range(3):
            try:
                reputation = self.__contract_obj.functions.getReputation(ip_address).call({
                    "from": self.__acc_address,
                    "gasPrice": self.__web3.to_wei("1", "gwei")
                })
                reputation = reputation if reputation else 1
                print(f"BLOCKCHAIN: Reputation of {ip_address} = {reputation}%", flush=True)
                return reputation
            except Exception as e:
                print(f"EXCEPTION: get_reputation({ip_address}) => {e}", flush=True)
                time.sleep(2)

    def get_raw_reputation(self, ip_address: str) -> list:
        for _ in range(3):
            try:
                numbers = self.__contract_obj.functions.getLastBasicReputation(ip_address).call({
                    "from": self.__acc_address,
                    "gasPrice": self.__web3.to_wei("1", "gwei")
                })
                print(f"BLOCKCHAIN: Raw reputation of {ip_address} = {numbers}", flush=True)
                return numbers
            except Exception as e:
                print(f"EXCEPTION: get_raw_reputation({ip_address}) => {e}", flush=True)
                time.sleep(2)

    def debug_getStrLst(self) -> list:
        for _ in range(3):
            try:
                strLst = self.__contract_obj.functions.getStrLst().call({
                    "from": self.__acc_address,
                    "gasPrice": self.__web3.to_wei("1", "gwei")
                })
                print(f"BLOCKCHAIN: getStrLst => {strLst}", flush=True)
                return strLst
            except Exception as e:
                print(f"EXCEPTION: debug_getStrLst() => {e}", flush=True)
                time.sleep(2)

    def debug_addStr(self, string):
        for _ in range(3):
            try:
                unsigned_trx = self.__contract_obj.functions.addStr(string).build_transaction(
                    {
                        "chainId": self.__web3.eth.chain_id,
                        "from": self.__acc_address,
                        "nonce": self.__web3.eth.get_transaction_count(
                            self.__web3.to_checksum_address(self.__acc_address)
                        ),
                        "gasPrice": self.__web3.to_wei("1", "gwei")
                    }
                )
                conf = self.__sign_and_deploy(unsigned_trx)
                json_reponse = self.__web3.to_json(conf)
                print(f"BLOCKCHAIN: added '{string}' to lst on blockchain", flush=True)
                return json_reponse
            except Exception as e:
                print(f"EXCEPTION: debug_addStr({string}) => {e}", flush=True)
                time.sleep(2)

    def _register_neighbors(self) -> str:
        for _ in range(3):
            print(f"neighbors:{self.__neighbors}, home_ip:{self.__home_ip}, address:{self.__acc_address}", flush=True)
            try:
                unsigned_trx = self.__contract_obj.functions.register_neighbors(self.__neighbors,
                                                                                self.__home_ip).build_transaction(
                    {
                        "chainId": self.__web3.eth.chain_id,
                        "from": self.__acc_address,
                        "nonce": self.__web3.eth.get_transaction_count(
                            self.__web3.to_checksum_address(self.__acc_address)
                        ),
                        "gasPrice": self.__web3.to_wei("1", "gwei")
                    }
                )
                conf = self.__sign_and_deploy(unsigned_trx)
                json_reponse = self.__web3.to_json(conf)
                print(f"BLOCKCHAIN: registered '{self.__neighbors}' as neighbors on blockchain", flush=True)
                return json_reponse
            except Exception as e:
                print(f"EXCEPTION: _register_neighbors({self.__neighbors}, {self.__home_ip}) => {e}", flush=True)
                time.sleep(2)

    def __testing(self):
        self._register_neighbors()
        for opinion, iteration in zip([22, 45, 98, 7, 68, 14, 79, 54, 33, 83], range(10)):
            print("*" * 50, f"BLOCKCHAIN TESTING: iteration {iteration}", "*" * 50, flush=True)
            start = time.time()
            ip = f"192.168.0.{iteration % 5}"

            self.debug_addStr(str(iteration % 5))
            self.debug_getStrLst()
            self.push_opinion(ip, opinion)
            self.__request_balance()
            self.get_reputation(ip)
            # self.get_raw_reputation(ip)

            print(f"BLOCKCHAIN: iteration {iteration} finished after {round(time.time() - start, 2)}s", flush=True)

        print("*" * 50, f"BLOCKCHAIN TESTING: FINISHED", "*" * 50, flush=True)
