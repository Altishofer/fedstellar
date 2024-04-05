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

from eth_account import Account
from web3 import Web3
from web3.middleware import construct_sign_and_send_raw_middleware
from web3.middleware import geth_poa_middleware

from tabulate import tabulate

from fedstellar.learning.aggregators.aggregator import Aggregator
from fedstellar.learning.aggregators.helper import cosine_metric, euclidean_metric, minkowski_metric, manhattan_metric, \
    pearson_correlation_metric, jaccard_metric


def pearson_correlation_opinion(local_model, untrusted_model):
    metric = pearson_correlation_metric(local_model, untrusted_model)
    return max(min(int(metric * 100), 100), 0)


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

        print_with_frame("BLOCKCHAIN AGGREGATION: START")

        if not len(model_obj_collection):
            logging.error("[BlockchainReputation] Trying to aggregate models when there are no models")
            return None

        local_model = self.__learner.get_parameters()
        #local_weight = self.__learner.get_num_samples()[0]

        current_models = {node: submodel for subnodes, (submodel, weight) in model_obj_collection.items()
                          for node in subnodes.split() if node in self.__neighbors}

        for subnodes, (submodel, weight) in model_obj_collection.items():
            nodes = subnodes.split()
            print(nodes, flush=True)


        if not len(current_models):
            logging.error("[BlockchainReputation] Trying to aggregate models when there are no models")
            return None

        current_models[self.node_name] = local_model

        final_model = {layer: torch.zeros_like(param) for layer, param in local_model.items()}

        neighbor_names = [name for name in current_models.keys() if name != self.node_name]

        # for name in neighbor_names:
        #     print(f"ENDBOSS: {name} = {self.__learner.endboss(current_models[name])}")

        metric_values = {name: self.minkowski_opinion(local_model, current_models[name]) for name in neighbor_names}

        opinion_values = {name: max(min(round((1 - metric) * 100), 100), 0) for name, metric in metric_values.items()}

        # initial_metric = self.__learner. (local_model)
        # initial_opinion = max(min(round((1 - initial_metric) * 100), 100), 0)

        OPINION_METRIC = "Minkowski Distance"
        print(f"\n{'-' * 25} QUALITY METRIC {'-' * 25}", flush=True)
        rows = [[ip_address, metric] for ip_address, metric in metric_values.items()]
        # rows.append(["Worker Node", initial_metric])
        print(
            tabulate(
                rows,
                headers=["Neighbor Node", OPINION_METRIC],
                tablefmt="grid"
            )
        )

        self.__blockchain.push_opinions(opinion_values, "Normalized " + OPINION_METRIC)

        reputation_values = self.__blockchain.get_reputations([name for name in current_models.keys()])

        normalized_reputation_values = {name: round(reputation_values[name] / (
            ((sum(reputation_values.values()) if sum(reputation_values.values()) > 0 else 1))), 3) for
                                        name in reputation_values}


        print(f"\n{'-' * 25} GLOBAL REPUTATION {'-' * 25}", flush=True)
        print(
            tabulate(
                [[ip_address, reputation] for ip_address, reputation in reputation_values.items()],
                headers=["Neighbor Node", "Global Reputation"],
                tablefmt="grid"
            )
        )
        print(f"\n{'-' * 25} NORMALIZED REPUTATION {'-' * 25}", flush=True)
        print(
            tabulate(
                [[ip_address, reputation] for ip_address, reputation in normalized_reputation_values.items()],
                headers=["Neighbor Node", "Normalized Reputation"],
                tablefmt="grid"
            )
        )
        # print(f"AGGREGATION: Reputation for contributions: {reputation_values}", flush=True)
        # print(f"AGGREGATION: Normalized reputation for aggregation: {normalized_reputation_values}", flush=True)

        for name, model in current_models.items():
            for layer in final_model:
                final_model[layer] += model[layer] * normalized_reputation_values[name]  # * weights[name]

        # for layer in final_model:
        #     final_model[layer] /= total_weights

        final_metric = self.minkowski_opinion(local_model, final_model)

        print(f"\n{'-' * 25} FINAL MODEL {'-' * 25}", flush=True)
        print(
            tabulate(
                [["New Distance", final_metric]], #["Aggregated Model Loss", final_metric], ["Improvement", round(initial_metric - final_metric, 3)]],
                headers=["Key", "Value"],
                tablefmt="grid"
            )
        )

        print_with_frame("BLOCKCHAIN AGGREGATION: FINISHED")

        # return final_model if final_opinion > initial_opinion else local_model
        return final_model

    def loss_opinion(self, local_model, untrusted_model):
        avg_loss = self.__learner.endboss(untrusted_model)
        return max(min(round(avg_loss, 2), 1), 0)

    def euclidean_opinion(self, local_model, untrusted_model):
        metric = euclidean_metric(local_model, untrusted_model)
        return max(min(round(metric, 2), 1), 0)

    def minkowski_opinion(self, local_model, untrusted_model):
        metric = minkowski_metric(local_model, untrusted_model, p=2)
        print(f"{metric}", flush=True)
        return max(min(round((10 - metric) / 10, 2), 1), 0)

    def manhattan_opinion(self, local_model, untrusted_model):
        metric = manhattan_metric(local_model, untrusted_model)
        return max(min(round(metric, 2), 1), 0)

    def jaccard_opinion(self, local_model, untrusted_model):
        metric = jaccard_metric(local_model, untrusted_model)
        return max(min(round(metric, 2), 1), 0)


def print_with_frame(message):
    message_length = len(message)
    top_border = f"{' ' * 20}+{'-' * (message_length + 2)}+"
    middle_border = f"{'*' * 20}| {message} |{'*' * 20}"
    bottom_border = f"{' ' * 20}+{'-' * (message_length + 2)}+"
    print(top_border, flush=True)
    print(middle_border, flush=True)
    print(bottom_border, flush=True)


class Blockchain:

    def __init__(self, neighbors, home_address):
        print_with_frame("BLOCKCHAIN INITIALIZATION: START")

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

        self.__acc = self.__create_account()
        self.__web3 = self.__initialize_geth()
        self.__wait_for_blockchain()
        self.__request_funds_from_oracle()
        self.__verify_balance()
        self.__contract_obj = self.__get_contract_from_oracle()
        self.__register_neighbors()
        self.__verify_registration()
        # self.__verify_centrality()

        print_with_frame("BLOCKCHAIN INITIALIZATION: FINISHED")

    def __initialize_geth(self):
        web3 = Web3(Web3.HTTPProvider(self.__rpc_url, request_kwargs={'timeout': 30}))
        web3.middleware_onion.inject(geth_poa_middleware, layer=0)
        web3.middleware_onion.add(construct_sign_and_send_raw_middleware(self.__acc))
        web3.eth.default_account = self.__acc_address
        return web3

    def __wait_for_blockchain(self):
        print(f"{'-' * 25} CONNECT TO ORACLE {'-' * 25}", flush=True)
        for _ in range(20):
            try:
                r = requests.get(
                    url=f"{self.__oracle_url}/status",
                    headers=self.__header,
                    timeout=10
                )
                if r.status_code == 200:
                    print(f"ORACLE: Blockchain is ready", flush=True)
                    return
            except Exception as e:
                print(f"EXCEPTION: wait_for_blockchain() => not ready, sleep 5", flush=True)
                time.sleep(5)
        raise RuntimeError(f"ERROR: wait_for_blockchain() could not be resolved")

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
                    print(f"ORACLE: Initialized chain code: {json_response.get('address')}",
                          flush=True)
                    return self.__web3.eth.contract(
                        abi=json_response.get("abi"),
                        address=json_response.get("address")
                    )
            except Exception as e:
                print(f"EXCEPTION: get_contract_from_oracle() => {e}", flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: get_contract_from_oracle() could not be resolved")

    def __verify_centrality(self):
        for _ in range(3):
            try:
                r = requests.get(
                    url=f"{self.__oracle_url}/verify_centrality",
                    headers=self.__header,
                    timeout=10
                )
                if r.status_code == 200:
                    json_response = r.json()
                    if not json_response.get('valid'):
                        raise Exception
                    print(f"ORACLE: Successfully verified centrality values", flush=True)
                    return json_response.get('valid')
            except Exception as e:
                print(f"EXCEPTION: verify_centrality() => {e}", flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: verify_centrality() could not be resolved")

    def __create_account(self):
        print(f"{'-' * 25} REGISTER WORKING NODE {'-' * 25}", flush=True)
        acc = Account.create()
        web3 = Web3()
        self.__private_key = web3.to_hex(acc.key)
        self.__acc_address = web3.to_checksum_address(acc.address)
        print(f"WORKER NODE: Registered account: {self.__home_ip}", flush=True)
        print(f"WORKER NODE: Account address: {self.__acc_address}", flush=True)
        return acc

    def __request_funds_from_oracle(self) -> None:
        for _ in range(3):
            try:
                r = requests.post(
                    url=f"{self.__oracle_url}/faucet",
                    json={f"address": self.__acc_address},
                    headers=self.__header,
                    timeout=10
                )
                r = requests.post(
                    url=f"{self.__oracle_url}/faucet",
                    json={f"address": "0x39c72ef67B74d350DdEdC0F1de49D7e73E797871"},
                    headers=self.__header,
                    timeout=10
                )
                if r.status_code == 200:
                    return print(f"ORACLE: Received 500 ETH", flush=True)
            except Exception as e:
                print(f"EXCEPTION: create_account() => {e}", flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: create_account() could not be resolved")

    def __verify_balance(self) -> None:
        for _ in range(3):
            try:
                balance = self.__web3.eth.get_balance(self.__acc_address, "latest")
                balance_eth = self.__web3.from_wei(balance, "ether")
                print(f"BLOCKCHAIN: Current balance of node = {balance_eth} ETH", flush=True)
                if balance_eth <= 0:
                    self.__request_funds_from_oracle()
                    raise Exception("Funds could not be verified")
                return print(f"BLOCKCHAIN: Successfully verified balance of {balance_eth} ETH", flush=True)
            except Exception as e:
                print(f"EXCEPTION: verify_balance() => {e}", flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: verify_balance() could not be resolved")

    def __sign_and_deploy(self, trx_hash):
        s_tx = self.__web3.eth.account.sign_transaction(trx_hash, private_key=self.__private_key)
        sent_tx = self.__web3.eth.send_raw_transaction(s_tx.rawTransaction)
        return self.__web3.eth.wait_for_transaction_receipt(sent_tx)

    def push_opinions(self, opinion_dict: dict, metric_name):
        print(f"\n{'-' * 25} REPORT LOCAL OPINION {'-' * 25}", flush=True)
        tuples = [(name, opinion) for name, opinion in opinion_dict.items()]
        for _ in range(3):
            try:
                unsigned_trx = self.__contract_obj.functions.rate_neighbors(tuples).build_transaction(
                    {
                        "chainId": self.__web3.eth.chain_id,
                        "from": self.__acc_address,
                        "nonce": self.__web3.eth.get_transaction_count(
                            self.__web3.to_checksum_address(self.__acc_address),
                            'pending'
                        ),
                        "gasPrice": self.__web3.to_wei("1", "gwei")
                    }
                )
                conf = self.__sign_and_deploy(unsigned_trx)
                json_response = self.__web3.to_json(conf)
                # for ip_address, opinion in opinion_dict.items():
                #     print(f"BLOCKCHAIN: Rating {ip_address} with {opinion}%", flush=True)
                print(
                    tabulate(
                        [[ip_address, opinion] for ip_address, opinion in opinion_dict.items()],
                        headers=["Neighbor Node", metric_name],
                        tablefmt="grid"
                    )
                )

                return json_response
            except Exception as e:
                print(f"EXCEPTION: push_opinions({opinion_dict}) => {e}", flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: push_opinion({opinion_dict}) could not be resolved")

    def get_reputations(self, ip_addresses: list) -> dict:
        print(f"\n{'-' * 25} REQUEST GLOBAL VIEW {'-' * 25}", flush=True)
        for _ in range(3):
            try:
                reputations = self.__contract_obj.functions.get_reputations(ip_addresses).call({
                    "from": self.__acc_address,
                    "gasPrice": self.__web3.to_wei("1", "gwei")
                })
                # if reputations:
                #     print(f"BLOCKCHAIN: Reputations: AVG = {reputations[0][4]}%, Stddev = {reputations[0][5]}",
                #           flush=True)
                # print(reputations)
                results = dict()
                for name, reputation, stddev_count, final_reputation, avg, stddev, centrality, difference, avg_difference, idx, stddev_opinions in reputations:
                    if name:
                        results[name] = final_reputation
                    # print(
                    #     f"BLOCKCHAIN: Reputation of {name} = {final_reputation}%, raw_reputation = {reputation}%, stddev_cnt < {stddev_count + 1}, centrality = {centrality}%, difference = {difference}, avg_difference = {avg_difference}, idx = {idx}",
                    #     flush=True)

                print(
                    tabulate(
                        [[name, reputation, stddev_count, final_reputation, avg, stddev, centrality, difference,
                          avg_difference, idx, stddev_opinions] for
                         name, reputation, stddev_count, final_reputation, avg, stddev, centrality, difference, avg_difference, idx, stddev_opinions
                         in reputations],
                        headers=["name", "reputation", "stddev_count", "final_reputation", "avg", "stddev",
                                 "centrality", "difference", "avg_difference", "idx", "stddev_opinions"],
                        tablefmt="grid",
                        maxcolwidths=[None, 8]
                    )
                )

                return results

            except Exception as e:
                print(f"EXCEPTION: get_reputations({ip_addresses}) => {e}", flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: get_reputations({ip_addresses}) could not be resolved")

    def __register_neighbors(self) -> str:
        print(f"{'-' * 25} REGISTER LOCAL TOPOLOGY {'-' * 25}", flush=True)
        for _ in range(3):
            try:
                unsigned_trx = self.__contract_obj.functions.register_neighbors(self.__neighbors,
                                                                                self.__home_ip).build_transaction(
                    {
                        "chainId": self.__web3.eth.chain_id,
                        "from": self.__acc_address,
                        "nonce": self.__web3.eth.get_transaction_count(
                            self.__web3.to_checksum_address(self.__acc_address),
                            'pending'
                        ),
                        "gasPrice": self.__web3.to_wei("1", "gwei")
                    }
                )
                conf = self.__sign_and_deploy(unsigned_trx)
                json_reponse = self.__web3.to_json(conf)
                for neighbor in self.__neighbors:
                    print(f"BLOCKCHAIN: Registered neighbor: {neighbor}", flush=True)
                return json_reponse
            except Exception as e:
                print(
                    f"EXCEPTION: _register_neighbors({self.__neighbors}, {self.__home_ip}) => {e}",
                    flush=True)
                if self.__verify_balance() == 0:
                    print(f"EXCEPTION: Request funds from Oracle", flush=True)
                    self.__request_funds_from_oracle()
                time.sleep(4)
        raise RuntimeError(f"ERROR: _register_neighbors({self.__neighbors}, {self.__home_ip})")

    def __verify_registration(self) -> None:
        for _ in range(3):
            try:
                confirmation = self.__contract_obj.functions.confirm_registration().call({
                    "from": self.__acc_address,
                    "gasPrice": self.__web3.to_wei("1", "gwei")
                })
                if not confirmation:
                    self.__register_neighbors()
                    raise Exception("Registration could not be confirmed")
                return print(f"BLOCKCHAIN: Verified registration", flush=True)
            except Exception as e:
                print(
                    f"EXCEPTION: _verify_registration() => {e}",
                    flush=True)
                time.sleep(4)
        raise RuntimeError(f"ERROR: _verify_registration()")
