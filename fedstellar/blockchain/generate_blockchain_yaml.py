import os.path
import random
import shutil
import textwrap
import json
from datetime import datetime
from web3 import Web3
from eth_keys import keys

w3 = Web3()


class Geth:

    def __init__(self, n_validator=3, config_dir=".", input_dir="."):
        self.__input_dir = input_dir
        self.__config_dir = config_dir
        self.__boot_id = None
        self.__boot_ip = "172.25.0.101"
        self.__rpc_ip = "172.25.0.104"
        self.__oracle_ip = "172.25.0.105"
        self.__yaml = str()
        self.__reserved_sockets = list()

        self.__genesis = self.__load_genesis()
        self.__setup_dir()
        self.__add_boot()
        self.__add_validator(n_validator)
        self.__add_rpc()
        self.__add_oracle()
        self.__export_config()

    def __setup_dir(self) -> None:
        if not os.path.exists(self.__config_dir):
            os.makedirs(self.__config_dir, exist_ok=True)

    def __get_unreserved_socket(self):
        for _ in range(100):
            ip = random.randint(10, 254)
            port = random.randint(30310, 30360)
            reserved_ip = [socket[0] for socket in self.__reserved_sockets]
            reserved_ports = [socket[1] for socket in self.__reserved_sockets]
            if ip not in reserved_ip and port not in reserved_ports:
                self.__reserved_sockets.append((ip, port))
                return ip, port
        raise Exception("Finding unreserved socket address failed")

    def __copy_dir(self, source):
        curr_path = os.path.dirname(os.path.abspath(__file__))
        if not os.path.exists(self.__config_dir):
            os.makedirs(self.__config_dir, exist_ok=True)
        target_dir = os.path.join(self.__config_dir, source)
        source_dir = os.path.join(curr_path, source)
        shutil.copytree(str(source_dir), target_dir, dirs_exist_ok=True)

    @staticmethod
    def __load_genesis() -> dict:
        return {
            "config": {
                "chainId": 19265019,
                "homesteadBlock": 0,
                "eip150Block": 0,
                "eip155Block": 0,
                "eip158Block": 0,
                "byzantiumBlock": 0,
                "constantinopleBlock": 0,
                "petersburgBlock": 0,
                "istanbulBlock": 0,
                "muirGlacierBlock": 0,
                "berlinBlock": 0,
                "clique": {
                    "period": 0,
                    "epoch": 10000
                }
            },
            "nonce": "0x0",
            "timestamp": "0x5a8efd25",
            "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000187c1c14c75bA185A59c621Fbe5dda26D488852DF20C144e8aE3e1aCF7071C4883B759D1B428e7930000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            "gasLimit": "9000000000000",  # "8000000" is default for gETH but to low for heavy load
            "difficulty": "0x1",
            "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "coinbase": "0x0000000000000000000000000000000000000000",
            "alloc": {
                "0x61DE01FcD560da4D6e05E58bCD34C8Dc92CE36D1": {
                    "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
                }
            },
            "number": "0x0",
            "gasUsed": "0x0",
            "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
        }

    def __add_boot(self):
        acc = w3.eth.account.create()
        self.__boot_id = str(keys.PrivateKey(acc.key).public_key)[2:]
        self.__yaml += textwrap.dedent(f"""
            geth-bootnode:
                hostname: geth-bootnode
                environment:
                  - nodekeyhex={w3.to_hex(acc.key)[2:]}
                build:
                  dockerfile: {self.__input_dir}/geth/boot.dockerfile
                container_name: boot
                networks:
                  chainnet:
                    ipv4_address: {self.__boot_ip}
            """)

    def __add_validator(self, cnt):
        validator_addresses = list()

        for id in range(cnt):
            acc = w3.eth.account.create()
            validator_addresses.append(acc.address[2:])
            ip, port = self.__get_unreserved_socket()

            self.__yaml += textwrap.dedent(f"""
                geth-validator-{id}:
                    hostname: geth-validator-{id}
                    depends_on:
                      - geth-bootnode
                    environment:
                      - address={acc.address}
                      - bootnodeId={self.__boot_id}
                      - bootnodeIp={self.__boot_ip}
                      - port={port}
                    build:
                      dockerfile: {self.__input_dir}/geth/validator.dockerfile
                      args:
                        privatekey: {w3.to_hex(acc.key)[2:]}
                        password: {w3.to_hex(w3.eth.account.create().key)}
                    container_name: validator_{id}
                    networks:
                      chainnet:
                        ipv4_address: 172.25.0.{ip}
                """)

        extra_data = "0x" + "0" * 64 + "".join([a for a in validator_addresses]) + 65 * "0" + 65 * "0"
        self.__genesis["extraData"] = extra_data


    def __add_oracle(self):
        acc = w3.eth.account.create()

        self.__genesis["alloc"] = {acc.address: {
            "balance": "0x200000000000000000000000000000000000000000000000000000000000000"
        }}

        self.__yaml += textwrap.dedent(f"""
            oracle:
               hostname: oracle
               depends_on:
                 - geth-rpc 
                 - geth-bootnode
               environment:
                 - PRIVATE_KEY={w3.to_hex(acc.key)[2:]}
                 - RPC_IP={self.__rpc_ip}
               build:
                 dockerfile: {self.__input_dir}/geth/oracle.dockerfile
                 context: {self.__input_dir}
               ports:
                 - 8081:8081
               container_name: oracle
               networks:
                 chainnet:
                   ipv4_address: {self.__oracle_ip}
            """)

    def __add_rpc(self):
        acc = w3.eth.account.create()
        self.__yaml += textwrap.dedent(f"""
            geth-rpc:
                 hostname: geth-rpc
                 depends_on:
                   - geth-bootnode
                 environment:
                   - address={acc.address}
                   - bootnodeId={self.__boot_id}
                   - bootnodeIp={self.__boot_ip}
                 build:
                   dockerfile: {self.__input_dir}/geth/rpc.dockerfile
                 ports:
                   - 8545:8545
                 container_name: rpc
                 networks:
                   chainnet:
                     ipv4_address: {self.__rpc_ip}
            """)

    def __add_network(self):
        self.__yaml += textwrap.dedent(f"""
            networks:
              chainnet:
                name: chainnet
                driver: bridge
                ipam:
                  config:
                  - subnet: 172.25.0.0/24
            """)

    def __export_config(self):
        finalStr = textwrap.indent(f"""{self.__yaml}""", "  ")
        self.__yaml = textwrap.dedent(f'''
                    version: "3.8"
                    name: blockchain
                    services:
                    ''')
        self.__yaml += finalStr
        self.__add_network()
        with open(f"{self.__config_dir}/blockchain-docker-compose.yml", "w+") as file:
            file.write(self.__yaml)

        with open(f"{self.__input_dir}/geth/genesis.json", "w+") as file:
            json.dump(self.__genesis, file, indent=4)

        source = os.path.join(self.__input_dir, "geth", "genesis.json")
        shutil.copy(source, os.path.join(self.__config_dir, "genesis.json"))

        source = os.path.join(self.__input_dir, "chaincode", "reputation_system.sol")
        shutil.copy(source, os.path.join(self.__config_dir, "reputation_system.sol"))


if __name__ == "__main__":
    b = Geth(
        n_validator=2,
        config_dir=os.path.join("deployments",
            datetime.now().strftime("%Y-%m-%d_%H-%M"))
    )
